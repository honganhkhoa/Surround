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
        let tinDay = try XCTUnwrap(SurroundTheme.christmasKeepsakes.board(for: .light).boardDepth)
        let tinNight = try XCTUnwrap(SurroundTheme.christmasKeepsakes.board(for: .dark).boardDepth)
        for depth in [nebula, day, night, frostDay, frostNight, tinDay, tinNight] {
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
        XCTAssertEqual(tinDay.thicknessRatio, tinNight.thicknessRatio)
        XCTAssertEqual(tinDay.maximumThickness, tinNight.maximumThickness)
        XCTAssertEqual(tinDay.edgeStyle, .rolledTin)
        XCTAssertEqual(tinNight.edgeStyle, tinDay.edgeStyle)
        XCTAssertNotEqual(tinDay.upperFace, tinNight.upperFace)
        XCTAssertNotEqual(tinDay.lowerFace, tinNight.lowerFace)
    }

    /// What lines up with a board follows what BoardView draws in its frame:
    /// the face and the sidewall below it, never the shadow's fade.
    func testBoardDepthPlacementReportsTheDrawnFaceAndSidewall() throws {
        for theme: SurroundTheme in [.surroundStudio, .frostPine, .christmasKeepsakes] {
            for scheme: ColorScheme in [.light, .dark] {
                let depth = try XCTUnwrap(theme.board(for: scheme).boardDepth)
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
        }
    }

    /// Public games' cards and Home's Large tiles: the players' rows above and
    /// below a board that spans the column run edge to edge with it as drawn.
    func testBoardColumnRowsMeetTheDrawnBoard() throws {
        for theme: SurroundTheme in [.surroundStudio, .christmasKeepsakes] {
            for scheme: ColorScheme in [.light, .dark] {
                let depth = try XCTUnwrap(theme.board(for: scheme).boardDepth)
                let board = BoardDepthPlacement(boardWidth: 19, boardHeight: 19, showsCoordinates: false,
                                                displayScale: 3, depth: depth)
                // A 337 pt card on an iPhone, with nothing limiting its height.
                let column = BoardColumnLayout.Column(width: 337, height: nil, rows: 60, board: board)
                let drawn = board.visibleBoard(in: CGRect(x: 0, y: 0, width: 337, height: 337))
                XCTAssertEqual(column.side, 337)
                XCTAssertEqual(column.rowWidth, drawn.width, accuracy: 0.001)
                XCTAssertLessThan(column.rowWidth, column.side, "The rows follow this material's inset face")
                if theme == .surroundStudio {
                    XCTAssertLessThan(column.rowWidth, 337 - 8, "Studio insets each side by about 5 pt")
                }
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
        }
    }

    /// Compact boards keep their exact slot, including rectangular previews;
    /// disabling depth for a widget must preserve that footprint at any size.
    func testBoardDepthKeepsCompactAndDisabledFootprintsUnchanged() {
        let depths: [BoardDepth?] = [nil, SurroundTheme.nebulaPearl.board.boardDepth,
                                    SurroundTheme.surroundStudio.board(for: .light).boardDepth,
                                    SurroundTheme.surroundStudio.board(for: .dark).boardDepth,
                                    SurroundTheme.frostPine.board(for: .light).boardDepth,
                                    SurroundTheme.frostPine.board(for: .dark).boardDepth,
                                    SurroundTheme.christmasKeepsakes.board(for: .light).boardDepth,
                                    SurroundTheme.christmasKeepsakes.board(for: .dark).boardDepth,
                                    SurroundTheme.goldenCrumb.board(for: .light).boardDepth]
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
                          XCTUnwrap(SurroundTheme.frostPine.board(for: .dark).boardDepth),
                          XCTUnwrap(SurroundTheme.christmasKeepsakes.board(for: .light).boardDepth),
                          XCTUnwrap(SurroundTheme.christmasKeepsakes.board(for: .dark).boardDepth),
                          XCTUnwrap(SurroundTheme.goldenCrumb.board(for: .light).boardDepth)]
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
                          XCTUnwrap(SurroundTheme.surroundStudio.board.boardDepth),
                          XCTUnwrap(SurroundTheme.christmasKeepsakes.board(for: .light).boardDepth),
                          XCTUnwrap(SurroundTheme.christmasKeepsakes.board(for: .dark).boardDepth)]
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
                          XCTUnwrap(SurroundTheme.surroundStudio.board.boardDepth),
                          XCTUnwrap(SurroundTheme.christmasKeepsakes.board(for: .light).boardDepth),
                          XCTUnwrap(SurroundTheme.christmasKeepsakes.board(for: .dark).boardDepth)]
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
                          XCTUnwrap(SurroundTheme.surroundStudio.board(for: .dark).boardDepth),
                          XCTUnwrap(SurroundTheme.christmasKeepsakes.board(for: .light).boardDepth),
                          XCTUnwrap(SurroundTheme.christmasKeepsakes.board(for: .dark).boardDepth)]
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
               "NightGardenBlackStone", "NightGardenWhiteStone",
               "ReefLightBlackStone", "ReefLightWhiteStone",
               "KoiPondBlackStone", "KoiPondWhiteStone",
               "GoldenCrumbBlackStone", "GoldenCrumbWhiteStone",
               "ChristmasKeepsakesRubyStone", "ChristmasKeepsakesIvoryStone"]
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

    func testKoiPondPanelFramesFollowTheLeadingEdgeOfTheGame() {
        let game = CGRect(x: 40, y: 16, width: 200, height: 120)
        let panel = CGRect(x: 20, y: 8, width: 50, height: 60)
        XCTAssertEqual(KoiPondGameLayout.panelFrames([panel], in: game, direction: .leftToRight),
                       [CGRect(x: 60, y: 24, width: 50, height: 60)])
        XCTAssertEqual(KoiPondGameLayout.panelFrames([panel], in: game, direction: .rightToLeft),
                       [CGRect(x: 170, y: 24, width: 50, height: 60)])
    }

    func testKoiPondSwimClockResumesAtItsFrozenPose() {
        var clock = KoiPondSwimClock()
        XCTAssertEqual(clock.elapsed(at: 10), 0)
        clock.setRunning(true, at: 10)
        clock.setRunning(true, at: 11)
        XCTAssertEqual(clock.elapsed(at: 14.5), 4.5)
        clock.setRunning(false, at: 14.5)
        clock.setRunning(false, at: 50)
        XCTAssertEqual(clock.elapsed(at: 125), 4.5)
        clock.setRunning(true, at: 125)
        XCTAssertEqual(clock.elapsed(at: 125), 4.5)
        XCTAssertEqual(clock.elapsed(at: 127), 6.5)
    }

    /// Physical layout measured on an undivided landscape phone. Hiding the top
    /// bar gives the game 78 more points while the outer window stays put.
    private func koiZenLayout(in window: CGRect, zen: Bool) -> (water: CGRect, board: CGRect, panels: [CGRect]) {
        let compact = window.width < 1000
        let water: CGRect
        if compact {
            let top: CGFloat = zen ? 0 : 78
            water = CGRect(x: 62, y: top, width: window.width - 124, height: window.height - top - 20)
        } else {
            water = window
        }
        let plan = GameDetailLayoutPlan(size: water.size, compact: compact, zen: zen, analyze: false,
                                        chat: false, hidesBoard: false, keyboard: false, accessibility: false, foldsClock: false)
        let board = plan[.board].offsetBy(dx: water.minX, dy: water.minY)
        let panels = KoiPondGameLayout.panelFrames([plan[.clocks], plan[.status]].filter { !$0.isEmpty },
                                                  in: water, direction: .leftToRight)
        return (water, board, panels)
    }

    func testKoiPondKeepsTheSameSchoolAndTrajectoriesAcrossZen() {
        for size in [CGSize(width: 956, height: 440), CGSize(width: 1180, height: 714)] {
            let window = CGRect(origin: .zero, size: size)
            let play = koiZenLayout(in: window, zen: false), zen = koiZenLayout(in: window, zen: true)
            XCTAssertNotEqual(zen.board, play.board)
            XCTAssertNotEqual(zen.panels, play.panels)
            for startsInZen in [false, true] {
                let session = KoiPondSwimSession(seed: 31)
                func routes(zen useZen: Bool, at time: TimeInterval) -> [KoiPondSwimRoute] {
                    let layout = useZen ? zen : play
                    return session.routes(for: .OGS(26268404), window: window, water: layout.water, board: layout.board,
                                          detailed: true, avoiding: layout.panels, elapsed: time)
                }
                let baseline = routes(zen: startsInZen, at: 0)
                XCTAssertEqual(baseline.count, 4)
                for (index, time) in [13.20, 13.24, 13.26, 15.0, 7200.0, 7200.05].enumerated() {
                    let isZen = index.isMultiple(of: 2) ? !startsInZen : startsInZen
                    let after = routes(zen: isZen, at: time)
                    XCTAssertEqual(after.map(\.id), baseline.map(\.id))
                    for (old, new) in zip(baseline, after) {
                        XCTAssertEqual(new.length, old.length)
                        XCTAssertEqual(new.opacity, old.opacity)
                        for offset in [0, 0.05, 2.75, 36.0] {
                            XCTAssertEqual(new.pose(at: time + offset), old.pose(at: time + offset))
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testKoiPondFrozenSceneKeepsItsPixelsAcrossZen() throws {
        let window = CGRect(x: 0, y: 0, width: 956, height: 440)
        let session = KoiPondSwimSession(seed: 31)
        let play = koiZenLayout(in: window, zen: false)
        _ = session.routes(for: .OGS(26268404), window: window, water: play.water, board: play.board,
                           detailed: true, avoiding: play.panels, elapsed: 0, reduceMotion: true)
        func pixels(zen: Bool) throws -> [UInt8] {
            let layout = koiZenLayout(in: window, zen: zen)
            let board = BoardSceneShadowRegion(bounds: layout.board, isDetailed: true, cellSize: layout.board.width / 20)
            let pond = KoiPondScene(scheme: .light, boards: [board], gameArea: layout.water,
                                    controlReservations: layout.panels, swimSession: session, gameID: .OGS(26268404))
                .frame(width: window.width, height: window.height)
            return try nativeMaterialPixels(pond, scale: 1).pixels
        }
        let initial = try pixels(zen: false)
        // Pause the actual scene clock at a nonzero instant, as Reduce Motion does.
        session.setRunning(true, at: 0)
        session.setRunning(false, at: 13.2)
        let paused = try pixels(zen: false)
        XCTAssertFalse(initial == paused, "The control frames must contain moving koi")
        XCTAssertTrue(try pixels(zen: true) == paused, "Entering Zen moved the paused fish")
        XCTAssertTrue(try pixels(zen: false) == paused, "Leaving Zen moved the paused fish")
    }

    @MainActor
    func testKoiPondOpensWithSwimmingArrivalsOrAPopulatedReducedMotionScene() throws {
        let window = CGRect(x: 0, y: 0, width: 440, height: 760)
        let face = BoardSceneShadowRegion(bounds: CGRect(x: 10, y: 170, width: 420, height: 420), isDetailed: true)
        func pixels(_ session: KoiPondSwimSession, measured: Bool, reduceMotion: Bool) throws -> [UInt8] {
            _ = session.routes(for: nil, window: window, water: window, board: measured ? face.faceBounds : nil,
                               detailed: true, avoiding: [], elapsed: 0, reduceMotion: reduceMotion)
            let scene = KoiPondScene(scheme: .light, boards: measured ? [face] : [], gameArea: window, swimSession: session)
                .frame(width: window.width, height: window.height)
            return try nativeMaterialPixels(scene, scale: 1).pixels
        }
        let session = KoiPondSwimSession(seed: 31)
        let empty = try pixels(session, measured: false, reduceMotion: false)
        let arrival = try pixels(session, measured: true, reduceMotion: false)
        XCTAssertTrue(empty == arrival, "Receiving the first board measurement must not paint a koi in open water")
        func changedPixels(_ sample: [UInt8]) -> Int {
            stride(from: 0, to: empty.count, by: 4).filter { i in
                (0..<3).contains { abs(Int(sample[i + $0]) - Int(empty[i + $0])) > 8 }
            }.count
        }
        let time = try XCTUnwrap((1...180).map(Double.init).first { time in
            session.planned.contains { window.insetBy(dx: 45, dy: 70).contains($0.pose(at: time).center) }
        })
        session.setRunning(true, at: 0)
        session.setRunning(false, at: time)
        XCTAssertGreaterThan(try changedPixels(pixels(session, measured: true, reduceMotion: false)), 100)
        let still = try pixels(KoiPondSwimSession(seed: 31), measured: true, reduceMotion: true)
        XCTAssertGreaterThan(changedPixels(still), 100, "A fresh Reduce Motion pond must already contain visible fish")
    }

    func testKoiPondWaitsForTheFirstBoardAndSurvivesMissingZenAnchors() throws {
        let window = CGRect(x: 0, y: 0, width: 956, height: 440)
        let play = koiZenLayout(in: window, zen: false)
        let session = KoiPondSwimSession(seed: 31)
        func routes(_ session: KoiPondSwimSession, game: Int, board: CGRect?, at time: TimeInterval) -> [KoiPondSwimRoute] {
            session.routes(for: .OGS(game), window: window, water: play.water, board: board,
                           detailed: true, avoiding: play.panels, elapsed: time)
        }
        XCTAssertTrue(routes(session, game: 1, board: nil, at: 0).isEmpty)
        let initial = routes(session, game: 1, board: play.board, at: 2)
        let measured = routes(KoiPondSwimSession(seed: 31), game: 1, board: play.board, at: 2)
        let absent = routes(session, game: 1, board: nil, at: 6)
        XCTAssertEqual(initial.count, 4)
        try assertKoiEnterFromTheEdge(initial, in: window, at: 2)
        XCTAssertEqual(initial.map { $0.pose(at: 2) }, measured.map { $0.pose(at: 2) })
        XCTAssertEqual(initial.map(\.length), measured.map(\.length))
        XCTAssertEqual(absent.map(\.id), initial.map(\.id))
        XCTAssertEqual(absent.map { $0.pose(at: 6) }, initial.map { $0.pose(at: 6) })

        let restored = routes(session, game: 1, board: koiZenLayout(in: window, zen: true).board, at: 7)
        XCTAssertEqual(restored.map { $0.pose(at: 7) }, initial.map { $0.pose(at: 7) })
        XCTAssertTrue(routes(session, game: 2, board: nil, at: 8).isEmpty)
        let next = routes(session, game: 2, board: play.board, at: 9)
        let independent = routes(KoiPondSwimSession(seed: 31), game: 2, board: play.board, at: 9)
        XCTAssertEqual(next.count, 4)
        try assertKoiEnterFromTheEdge(next, in: window, at: 9)
        XCTAssertEqual(next.map { $0.pose(at: 9) }, independent.map { $0.pose(at: 9) })
        XCTAssertNotEqual(next.map { $0.pose(at: 9) }, initial.map { $0.pose(at: 9) })
    }

    /// A fish can change course invisibly beyond the window. In visible water,
    /// compare the pose actually drawn, including the current size of its body.
    private func assertKoiStayInPlace(_ before: [KoiPondSwimRoute], _ after: [KoiPondSwimRoute],
                                      in window: CGRect, at time: TimeInterval,
                                      file: StaticString = #filePath, line: UInt = #line) throws {
        func visible(_ route: KoiPondSwimRoute) -> Bool {
            route.isPresent(at: time) && route.bounds(at: time).intersects(window)
        }
        XCTAssertEqual(before.filter(visible).map(\.id), after.filter(visible).map(\.id),
                       "A layout change must preserve visible fish and their drawing order", file: file, line: line)
        for previous in before where visible(previous) {
            let current = try XCTUnwrap(after.first { $0.id == previous.id }, file: file, line: line)
            let a = previous.pose(at: time), b = current.pose(at: time)
            XCTAssertEqual(b.center.x, a.center.x, accuracy: 0.05, file: file, line: line)
            XCTAssertEqual(b.center.y, a.center.y, accuracy: 0.05, file: file, line: line)
            XCTAssertEqual(b.length, a.length, accuracy: 0.05, file: file, line: line)
            XCTAssertEqual(cos(b.heading - a.heading), 1, accuracy: 0.00001, file: file, line: line)
            XCTAssertEqual(b.beat, a.beat, accuracy: 0.00001, file: file, line: line)
            XCTAssertEqual(b.tailAmplitude, a.tailAmplitude, accuracy: 0.00001, file: file, line: line)
            XCTAssertEqual(b.bend, a.bend, accuracy: 0.00001, file: file, line: line)
        }
    }

    private func assertKoiEnterFromTheEdge(_ routes: [KoiPondSwimRoute], in window: CGRect, at start: TimeInterval,
                                            file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertFalse(routes.isEmpty, file: file, line: line)
        for route in routes {
            XCTAssertFalse(route.bounds(at: start).intersects(window), "The entire new koi starts outside",
                           file: file, line: line)
            let samples = stride(from: start, through: start + route.duration + 2, by: 0.2)
            let first = try XCTUnwrap(samples.first { route.bounds(at: $0).intersects(window) }, file: file, line: line)
            XCTAssertFalse(window.contains(route.bounds(at: first)), "The nose must arrive before the whole fish",
                           file: file, line: line)
            XCTAssertTrue(samples.contains { window.contains(route.pose(at: $0).center) },
                          "The koi must continue swimming into view", file: file, line: line)
        }
    }

    func testKoiPondPanelAndDivisionChangesKeepVisibleKoiInPlace() throws {
        let window = CGRect(x: 0, y: 0, width: 956, height: 440)
        let play = koiZenLayout(in: window, zen: false)
        let chat = KoiPondSwimLayout(panel: .chat), hidden = KoiPondSwimLayout(panel: .chat, hidesChatBoard: true)
        let layouts = [chat, hidden, KoiPondSwimLayout(panel: .analyze), KoiPondSwimLayout(divided: true), .init()]
        for paused in [false, true] {
            let session = KoiPondSwimSession(seed: 31)
            func routes(_ layout: KoiPondSwimLayout, at time: TimeInterval) -> [KoiPondSwimRoute] {
                let board = layout.hidesChatBoard ? window.insetBy(dx: window.width * 0.16, dy: window.height * 0.19)
                                                  : (layout.panel == .playerInfo ? play.board : play.board.insetBy(dx: 44, dy: 44))
                return session.routes(for: .OGS(31), window: window, water: play.water, board: board, detailed: true,
                                      avoiding: play.panels, layout: layout, elapsed: time, reduceMotion: paused)
            }
            var old = routes(.init(), at: 0)
            let time = try XCTUnwrap((0...360).map(Double.init).first { time in
                old.filter { window.contains($0.pose(at: time).center) }.count >= 2
            })
            XCTAssertFalse(paused && time != 0, "A fresh Reduce Motion pond needs visible residents")
            for (index, layout) in (layouts + layouts.reversed()).enumerated() {
                let instant = paused ? time : time + Double(index) * 0.25
                let next = routes(layout, at: instant)
                try assertKoiStayInPlace(old, next, in: window, at: instant)
                old = next
            }
        }
    }

    func testKoiPondNewUnderwaterResidentsArriveFromOutsideTheWindow() throws {
        let session = KoiPondSwimSession(seed: 41)
        let window = CGRect(x: 0, y: 0, width: 440, height: 956)
        let board = CGRect(x: 0, y: 280, width: 440, height: 440)
        let compact = session.routes(for: .OGS(100), window: window, water: window, board: board,
                                     detailed: false, avoiding: [], elapsed: 0)
        XCTAssertFalse(compact.isEmpty)
        XCTAssertFalse(compact.contains(where: \.submerged))
        let full = session.routes(for: .OGS(100), window: window, water: window, board: board,
                                  detailed: true, avoiding: [], layout: .init(divided: true), elapsed: 17)
        let newcomers = full.filter { $0.submerged }
        XCTAssertEqual(newcomers.count, 2)
        try assertKoiStayInPlace(compact, full, in: window, at: 17)
        try assertKoiEnterFromTheEdge(newcomers, in: window, at: 17)

        let time = try XCTUnwrap((18...300).map(Double.init).first { time in
            newcomers.contains { window.contains($0.pose(at: time).center) }
        })
        let closing = session.routes(for: .OGS(100), window: window, water: window, board: board,
                                     detailed: false, avoiding: [], elapsed: time)
        try assertKoiStayInPlace(full, closing, in: window, at: time)
        for departing in closing where departing.submerged && departing.isPresent(at: time) {
            let end = try XCTUnwrap(stride(from: time, through: time + departing.duration + 180, by: 0.25)
                .first { !departing.isPresent(at: $0) }, "The old underwater route must eventually finish")
            XCTAssertFalse(window.contains(departing.pose(at: end - 0.25).center),
                           "Removing a resident while its body is still in open water makes it blink out")
        }
    }

    @MainActor
    func testKoiPondKeepsTheFishInWindowCoordinatesWhenZenMovesTheCanvas() throws {
        let window = CGRect(x: 0, y: 0, width: 956, height: 440)
        let session = KoiPondSwimSession(seed: 31)
        let initial = koiZenLayout(in: window, zen: false)
        _ = session.routes(for: nil, window: window, water: initial.water, board: initial.board,
                           detailed: true, avoiding: initial.panels, elapsed: 0, reduceMotion: true)
        func fishMask(in canvas: CGRect, zen: Bool) throws -> [Bool] {
            let layout = koiZenLayout(in: window, zen: zen)
            func local(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -canvas.minX, dy: -canvas.minY) }
            let board = BoardSceneShadowRegion(bounds: local(layout.board), isDetailed: true)
            func pixels(withFish: Bool) throws -> [UInt8] {
                let pond = KoiPondScene(scheme: .light, boards: withFish ? [board] : [], gameArea: local(layout.water),
                                        controlReservations: layout.panels.map(local), windowInScene: local(window),
                                        swimSession: withFish ? session : KoiPondSwimSession(seed: 0))
                    .frame(width: canvas.width, height: canvas.height)
                return try nativeMaterialPixels(pond, scale: 1).pixels
            }
            let fish = try pixels(withFish: true), water = try pixels(withFish: false)
            // Compare the same physical patch of water in both canvases. Subtract each
            // canvas's own water so a different background crop cannot look like a fish.
            return (90..<355).flatMap { y in
                (185..<830).map { x in
                    let i = ((y - Int(canvas.minY)) * Int(canvas.width) + x - Int(canvas.minX)) * 4
                    return (0..<3).contains { abs(Int(fish[i + $0]) - Int(water[i + $0])) > 10 }
                }
            }
        }
        let play = try fishMask(in: window, zen: false)
        let shifted = CGRect(x: 38, y: 27, width: 878, height: 398)
        let zen = try fishMask(in: shifted, zen: true)
        let union = zip(play, zen).filter { $0 || $1 }.count
        let sameInk = zip(play, zen).filter { $0 && $1 }.count
        XCTAssertGreaterThan(union, 400)
        XCTAssertGreaterThan(Double(sameInk) / Double(max(1, union)), 0.9,
                             "Moving the local canvas must leave the actual koi silhouettes at the same window points")
    }

    func testKoiPondResizingAndRotationKeepVisibleFishMovingAfterHours() throws {
        let session = KoiPondSwimSession(seed: 31)
        func routes(in window: CGRect, at time: TimeInterval) -> [KoiPondSwimRoute] {
            let side = min(window.width, window.height) * 0.86
            let board = CGRect(x: window.midX - side / 2, y: window.midY - side / 2, width: side, height: side)
            return session.routes(for: .OGS(31), window: window, water: window, board: board,
                                  detailed: true, avoiding: [], elapsed: time)
        }
        let phone = CGRect(x: 0, y: 0, width: 440, height: 956)
        let narrow = CGRect(x: 0, y: 0, width: 437, height: 956)
        let landscape = CGRect(x: 0, y: 0, width: 956, height: 440)
        let expanded = CGRect(x: 0, y: 0, width: 1380, height: 1050)
        var old = routes(in: phone, at: 0)
        let common = phone.intersection(landscape)
        let start = try XCTUnwrap((0...360).map { 7200 + Double($0) }.first { time in
            old.contains { common.contains($0.pose(at: time).center) }
        })
        for (index, window) in [narrow, landscape, expanded, phone, expanded].enumerated() {
            let time = start + Double(index)
            let next = routes(in: window, at: time)
            try assertKoiStayInPlace(old, next, in: window, at: time)
            old = next
        }

        // An enlarged window can contain the old offscreen turn. Check the
        // complete handoff, including the first visible frames on the new course.
        for route in old {
            var previous = route.pose(at: start + 4)
            var previousVisible = route.bounds(at: start + 4).intersects(expanded)
            var swam = false
            for time in stride(from: start + 4.25, through: start + 4 + route.duration + 120, by: 0.25) {
                let pose = route.pose(at: time), bounds = route.bounds(at: time)
                let visible = route.isPresent(at: time) && bounds.intersects(expanded)
                if visible && previousVisible {
                    let displacement = hypot(pose.center.x - previous.center.x, pose.center.y - previous.center.y)
                    XCTAssertLessThan(displacement, max(previous.length, pose.length) * 0.10)
                    XCTAssertEqual(pose.length, previous.length, accuracy: 0.05)
                    swam = swam || displacement > 0.05
                } else if visible {
                    XCTAssertFalse(expanded.contains(bounds), "A returning koi must enter from the window edge")
                }
                previous = pose
                previousVisible = visible
            }
            XCTAssertTrue(swam, "Every resident should swim visibly in the larger window")
        }
    }

    func testKoiPondSlowSwimsFollowRepeatableButDistinctSeededRoutes() throws {
        let window = CGRect(x: 0, y: 0, width: 720, height: 900)
        let board = CGRect(x: 126, y: 240, width: 468, height: 468)
        func routes(seed: UInt64) -> [KoiPondSwimRoute] {
            KoiPondSwimSchool(seed: seed).routes(in: window, gameArea: window, board: board,
                                                detailed: true, avoiding: [])
        }
        let first = routes(seed: 27)
        let repeated = routes(seed: 27)
        XCTAssertEqual(first.count, 4)
        XCTAssertEqual(first.map(\.assetName), repeated.map(\.assetName))
        XCTAssertEqual(first.filter(\.submerged).count, 2)
        XCTAssertTrue(first.contains { !$0.submerged && $0.speed > 0 })
        XCTAssertTrue(first.contains { $0.submerged && $0.speed > 0 })
        for (left, right) in zip(first, repeated) {
            XCTAssertEqual(left.length, right.length)
            XCTAssertEqual(left.visibleWater, right.visibleWater)
            XCTAssertEqual(left.duration, right.duration)
            for time: TimeInterval in [0, 1.7, 8.4, 63] {
                XCTAssertEqual(left.pose(at: time), right.pose(at: time))
            }
        }

        // Compare where the fish goes over a whole circuit: a different
        // starting phase on an otherwise identical circuit is not a new path.
        func travelBounds(_ route: KoiPondSwimRoute) -> CGRect {
            (0..<240).reduce(.null) { bounds, sample in
                let center = route.pose(at: route.duration * Double(sample) / 240).center
                return bounds.union(CGRect(origin: center, size: CGSize(width: 0.01, height: 0.01)))
            }
        }
        let variants = routes(seed: 324)
        var different = false
        for route in first where route.duration > 0 {
            let alternate = try XCTUnwrap(variants.first { $0.submerged == route.submerged && $0.assetName == route.assetName })
            let a = travelBounds(route), b = travelBounds(alternate)
            if abs(a.minX - b.minX) > 2 || abs(a.minY - b.minY) > 2
                || abs(a.width - b.width) > 2 || abs(a.height - b.height) > 2 {
                different = true
            }
        }
        XCTAssertTrue(different, "Changing the session seed should change where at least one koi swims")
    }

    func testKoiPondSlowSwimsTravelNoseFirstAcrossTheVisiblePond() {
        let window = CGRect(x: 0, y: 0, width: 440, height: 956)
        let play = CGRect(x: 0, y: 116, width: 440, height: 768)
        let board = CGRect(x: 0, y: 285, width: 440, height: 440)
        let panels = [CGRect(x: 8, y: 125, width: 424, height: 96),
                      CGRect(x: 8, y: 229, width: 150, height: 50),
                      CGRect(x: 120, y: 728, width: 312, height: 50)]
        for seed: UInt64 in [2, 31, 129] {
            let routes = KoiPondSwimSchool(seed: seed).routes(in: window, gameArea: play, board: board,
                                                              detailed: true, avoiding: panels)
            XCTAssertEqual(routes.count, 4)
            for route in routes {
                XCTAssertGreaterThan(route.speed, 0)
                XCTAssertLessThan(route.speed, route.length * 0.16, "Slow swimming takes several seconds per body length")
                XCTAssertEqual(route.visibleWater, window)
                let steps = 512
                let interval = route.duration / Double(steps)
                let poses = (0...2 * steps).map { route.pose(at: Double($0) * interval) }
                var longest: CGFloat = 0
                // Continue in real time across the lap instead of wrapping the clock at its mean period.
                for start in stride(from: 0, to: steps, by: 8) {
                    let first = poses[start]
                    for step in 0..<steps {
                        let pose = poses[start + step]
                        guard (route.submerged ? board : window).contains(pose.center), !panels.contains(where: { $0.contains(pose.center) }),
                              cos(pose.heading - first.heading) > 0.5 else { break }
                        let forward = (pose.center.x - first.center.x) * cos(first.heading)
                            + (pose.center.y - first.center.y) * sin(first.heading)
                        longest = max(longest, forward)
                    }
                }
                XCTAssertGreaterThan(longest, 2 * route.length,
                                     "\(route.assetName) must visibly travel nose-first across the pond before turning")
                for index in 0..<(poses.count - 1) {
                    let a = poses[index], b = poses[index + 1]
                    let time = interval * Double(index)
                    if window.intersects(route.bounds(at: time)) {
                        let forward = (b.center.x - a.center.x) * cos(a.heading) + (b.center.y - a.center.y) * sin(a.heading)
                        XCTAssertGreaterThanOrEqual(forward, 0, "Every visible part of a pass must advance nose-first")
                    }
                    XCTAssertLessThan(hypot(b.center.x - a.center.x, b.center.y - a.center.y),
                                      2.4 * route.speed * interval, "The center must stay continuous throughout a stroke and across the lap")
                }
            }
        }
    }

    func testKoiPondStrokesVaryVisibleSpeedAndGlideWithAQuietTail() {
        let window = CGRect(x: 0, y: 0, width: 440, height: 956)
        let board = CGRect(x: 0, y: 285, width: 440, height: 440)
        let routes = KoiPondSwimSchool(seed: 31).routes(in: window, gameArea: window, board: board,
                                                       detailed: true, avoiding: [])
        XCTAssertEqual(routes.count, 4)
        let interval = 1.0 / 20
        var rhythms: [[CGFloat]] = []
        for route in routes {
            var speeds: [CGFloat] = [], amplitudes: [CGFloat] = []
            var quietSeconds = 0.0, longestVisibleGlide = 0.0, strongestVisibleStroke: CGFloat = 0
            var previousSpeed: CGFloat?, previousAmplitude: CGFloat?
            var strokeStartSpeed: CGFloat?, coastStartSpeed: CGFloat?
            var greatestPush: CGFloat = 0, greatestCoastLoss: CGFloat = 0
            for step in 0...3200 {
                let time = Double(step) * interval
                let current = route.pose(at: time), next = route.pose(at: time + interval)
                amplitudes.append(current.tailAmplitude)
                if current.tailAmplitude == 0 {
                    XCTAssertEqual(current.bend, 0, accuracy: 0.000001, "Steering flex must relax completely during a glide")
                }
                guard window.contains(current.center), window.contains(next.center) else {
                    previousSpeed = nil
                    previousAmplitude = nil
                    strokeStartSpeed = nil
                    coastStartSpeed = nil
                    quietSeconds = 0
                    continue
                }
                let dx = next.center.x - current.center.x, dy = next.center.y - current.center.y
                let forward = (dx * cos(current.heading) + dy * sin(current.heading)) / interval
                speeds.append(forward)
                strongestVisibleStroke = max(strongestVisibleStroke, current.tailAmplitude)
                if let previousSpeed {
                    XCTAssertLessThan(abs(forward - previousSpeed), route.speed * 0.25,
                                      "Propulsion must build and relax smoothly across consecutive visible samples")
                }
                if let previousAmplitude { XCTAssertLessThan(abs(current.tailAmplitude - previousAmplitude), 0.32) }
                previousSpeed = forward
                previousAmplitude = current.tailAmplitude
                if current.tailAmplitude == 0 && next.tailAmplitude == 0 {
                    if coastStartSpeed == nil { coastStartSpeed = forward }
                    greatestCoastLoss = max(greatestCoastLoss, (coastStartSpeed ?? forward) - forward)
                    strokeStartSpeed = nil
                    XCTAssertEqual(current.beat, next.beat, accuracy: 0.000001)
                    XCTAssertGreaterThan(forward, route.speed * 0.15, "A quiet-tailed koi must keep gliding nose-first")
                    quietSeconds += interval
                    longestVisibleGlide = max(longestVisibleGlide, quietSeconds)
                } else {
                    if strokeStartSpeed == nil { strokeStartSpeed = forward }
                    greatestPush = max(greatestPush, forward - (strokeStartSpeed ?? forward))
                    coastStartSpeed = nil
                    quietSeconds = 0
                }
            }
            XCTAssertGreaterThan(longestVisibleGlide, 0.9, "The tail must visibly settle between stroke bouts")
            XCTAssertGreaterThan(strongestVisibleStroke, 0.72)
            XCTAssertGreaterThan(greatestPush, route.speed * 0.25, "Tail strokes must generate forward momentum")
            XCTAssertGreaterThan(greatestCoastLoss, route.speed * 0.25, "The koi must gradually slow as it coasts")
            XCTAssertGreaterThan(speeds.count, 30)
            if !speeds.isEmpty {
                speeds.sort()
                XCTAssertGreaterThan(speeds[speeds.count * 9 / 10] - speeds[speeds.count / 10], route.speed * 0.25,
                                     "Visible forward speed should change across a swim cycle")
            }
            rhythms.append(amplitudes)
        }
        for i in rhythms.indices {
            for previous in rhythms.prefix(i) {
                let different = zip(previous, rhythms[i]).filter { abs($0 - $1) > 0.35 }.count
                XCTAssertGreaterThan(different, previous.count / 10, "The school must not stroke and glide in unison")
            }
        }
    }

    func testKoiPondSlowSwimsRespectSolidBoardsAndTheClosedDuoRail() {
        let window = CGRect(x: 0, y: 0, width: 240, height: 360)
        let content = CGRect(x: 0, y: 0, width: 192, height: 360)
        let board = CGRect(x: 10, y: 94, width: 176, height: 176)
        let routes = KoiPondSwimSchool(seed: 54).routes(in: window, gameArea: content, board: board,
                                                        detailed: false, avoiding: [content])
        let rail = CGRect(x: content.maxX, y: 0, width: window.width - content.width, height: window.height)
        XCTAssertFalse(routes.isEmpty)
        var visibleRailTravel: CGFloat = 0
        for route in routes {
            XCTAssertFalse(route.submerged, "Solid boards cannot show underwater residents")
            var positions = CGRect.null
            for sample in 0..<300 {
                let point = route.pose(at: route.duration * Double(sample) / 300).center
                if rail.contains(point) { positions = positions.union(CGRect(origin: point, size: CGSize(width: 1, height: 1))) }
            }
            if !positions.isNull { visibleRailTravel = max(visibleRailTravel, positions.height) }
        }
        XCTAssertGreaterThan(visibleRailTravel, 24, "A koi should move through the exposed rail beside the covered game")
    }

    /// Sample the actual pond first with no fish in the target and then as a
    /// planned route crosses it. Layout reservations are identical in both frames.
    @MainActor
    private func koiPondCrossing<Cover: View>(in probe: CGRect, reservations: [CGRect],
                                             viewport: CGRect? = nil,
                                             boardBounds: CGRect = CGRect(x: 0, y: 285, width: 440, height: 440),
                                             scheme: ColorScheme = .light, seed: UInt64 = 6,
                                             secondary: BoardSceneShadowRegion? = nil,
                                             @ViewBuilder cover: () -> Cover) throws -> (clear: UIImage, fish: UIImage) {
        let size = viewport?.size ?? CGSize(width: 440, height: 956)
        let board = BoardSceneShadowRegion(bounds: boardBounds, isDetailed: true, cellSize: boardBounds.width / 20)
        let school = KoiPondSwimSession(seed: seed)
        let pond = ZStack(alignment: .topLeading) {
            KoiPondScene(scheme: scheme, boards: [board] + [secondary].compactMap { $0 },
                         gameArea: viewport ?? CGRect(x: 0, y: 116, width: 440, height: 768),
                         controlReservations: reservations, swimSession: school)
            cover()
        }
        .environment(\.colorScheme, scheme)
        .frame(width: size.width, height: size.height)
        func render() throws -> UIImage { try XCTUnwrap(ImageRenderer(content: pond).uiImage) }
        _ = try render()
        XCTAssertEqual(school.planned.count, 4)
        let times = stride(from: 0.0, through: 1800.0, by: 0.5)
        let clearTime = try XCTUnwrap(times.first { time in
            !school.planned.contains { $0.isPresent(at: time) && $0.bounds(at: time).intersects(probe) }
        })
        func nearest(_ time: Double) -> CGFloat {
            school.planned.compactMap { route -> CGFloat? in
                guard route.isPresent(at: time), route.bounds(at: time).intersects(probe) else { return nil }
                let center = route.pose(at: time).center
                return hypot(center.x - probe.midX, center.y - probe.midY)
            }.min() ?? .infinity
        }
        let crossing = times.lazy.filter { $0 > clearTime }.map { (time: $0, distance: nearest($0)) }
            .filter { $0.distance.isFinite }.min { $0.distance < $1.distance }
        let crossingTime = try XCTUnwrap(crossing?.time, "The passing frame must contain a koi at the sampled gap")
        func advance(by seconds: Double) {
            school.setRunning(true, at: 0)
            school.setRunning(false, at: seconds)
        }
        advance(by: clearTime)
        let clear = try render()
        advance(by: crossingTime - clearTime)
        return (clear, try render())
    }

    private func koiPondClockFaces(in clocks: CGRect, stacked: Bool, direction: LayoutDirection = .leftToRight) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            ForEach([StoneColor.black, .white], id: \.self) { color in
                KoiPondPebbleChip(color: color, cornerRadius: 17)
                    .background(alignment: .bottom) {
                        KoiPondBambooLedge(compact: false, running: color == .black)
                            .offset(y: KoiPondBambooLedge.height - KoiPondBambooLedge.overlap)
                    }
            }
        }
        .environment(\.layoutDirection, direction)
        .frame(width: clocks.width, height: clocks.height)
        .position(x: clocks.midX, y: clocks.midY)
    }

    @MainActor
    private func koiPondChangedPixels(_ pair: (clear: UIImage, fish: UIImage), in probe: CGRect) throws -> Int {
        func sample(_ image: UIImage) throws -> [UInt8] {
            let tile = try XCTUnwrap(image.cgImage?.cropping(to: probe))
            return try nativeMaterialPixels(Image(decorative: tile, scale: 1), scale: 1).pixels
        }
        let base = try sample(pair.clear), fish = try sample(pair.fish)
        return stride(from: 0, to: base.count, by: 4).filter { i in
            (0..<3).contains { abs(Int(base[i + $0]) - Int(fish[i + $0])) > 8 }
        }.count
    }

    @MainActor
    func testKoiPondSwimsThroughTransparentPanelAndActionGaps() throws {
        let clocks = CGRect(x: 8, y: 125, width: 424, height: 96)
        let preview = CGRect(x: 8, y: 229, width: 424, height: 50)
        let actions = CGRect(x: 120, y: 728, width: 312, height: 50)
        let analysis = CGRect(x: 0, y: 728, width: 440, height: 50)
        let probes: [(label: String, reservation: CGRect, gap: CGRect)] = [
            ("Between the clock cards", clocks, CGRect(x: 217, y: 148, width: 6, height: 55)),
            ("Below the White clock’s inner rounded corner", clocks, CGRect(x: 224, y: 216, width: 5, height: 5)),
            ("Chat preview row", preview, CGRect(x: 180, y: 239, width: 72, height: 24)),
            ("Opaque Analyze toolbar", analysis, CGRect(x: 178, y: 741, width: 64, height: 24)),
            ("Vacant Next slot", actions, CGRect(x: 128, y: 741, width: 108, height: 24))
        ]
        for (label, reservation, probe) in probes {
            XCTAssertTrue(reservation.contains(probe))
            let pair = try koiPondCrossing(in: probe, reservations: [reservation]) {
                if reservation == clocks {
                    koiPondClockFaces(in: clocks, stacked: false)
                } else if reservation == preview {
                    RoundedRectangle(cornerRadius: 10).fill(.purple.opacity(0.08))
                        .frame(width: preview.width, height: preview.height).position(x: preview.midX, y: preview.midY)
                } else if reservation == analysis {
                    SurroundTheme.koiPond.panel.frame(width: analysis.width, height: analysis.height)
                        .position(x: analysis.midX, y: analysis.midY)
                }
            }
            let changed = try koiPondChangedPixels(pair, in: probe)
            if reservation == analysis {
                let bare = try koiPondCrossing(in: probe, reservations: [reservation]) { EmptyView() }
                XCTAssertGreaterThan(try koiPondChangedPixels(bare, in: probe), 100)
                XCTAssertEqual(changed, 0, "The Analyze toolbar's actual panel fill covers the fish")
            } else {
                XCTAssertGreaterThan(changed, Int(probe.width * probe.height * 0.06),
                                     "The fish must remain visible in the transparent part of the \(label) reservation")
            }
            if label == "Between the clock cards" {
                let underStone = CGRect(x: 224, y: probe.minY, width: 12, height: probe.height)
                let bare = try koiPondCrossing(in: probe, reservations: [reservation]) { EmptyView() }
                XCTAssertGreaterThan(try koiPondChangedPixels(bare, in: underStone), 20, "The koi also passes beneath White")
                XCTAssertEqual(try koiPondChangedPixels(pair, in: underStone), 0, "The stone face covers that part of the same koi")
                for (name, frame) in [("Open water between clock faces", pair.clear), ("Koi passing between clock faces", pair.fish)] {
                    let attachment = XCTAttachment(image: frame)
                    attachment.name = name
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    @MainActor
    func testKoiPondLandscapeStackAndAnalysisCornerExposeTheirOpenWater() throws {
        let viewport = CGRect(x: 0, y: 0, width: 1180, height: 714)
        for analyze in [false, true] {
            let plan = GameDetailLayoutPlan(size: viewport.size, compact: false, zen: false, analyze: analyze,
                                            chat: false, hidesBoard: false, keyboard: false, accessibility: false,
                                            foldsClock: false)
            func physical(_ slot: GameDetailLayoutPlan.Slot) -> CGRect {
                KoiPondGameLayout.panelFrames([plan[slot]], in: viewport, direction: .rightToLeft)[0]
            }
            let clocks = physical(.clocks), tree = physical(.analysis)
            let panels = [clocks, tree, physical(.analysisControls)].filter { !$0.isEmpty }
            XCTAssertTrue(analyze ? plan.verticalAnalysisTree : plan.stackedClocks)
            // Two points of open water remain beneath the upper card's bamboo.
            let gap = analyze ? CGRect(x: tree.minX, y: tree.minY, width: 4, height: 4)
                              : CGRect(x: clocks.midX - 35, y: clocks.midY + 2, width: 70, height: 2)
            let interior = analyze ? CGRect(x: tree.minX + 6, y: tree.minY + 4, width: 10, height: 7)
                                   : gap.offsetBy(dx: 0, dy: 10)
            func sample(foreground: Bool) throws -> (clear: UIImage, fish: UIImage) {
                try koiPondCrossing(in: gap, reservations: panels, viewport: viewport, boardBounds: physical(.board),
                                    scheme: .dark, seed: analyze ? 84 : 13) {
                    if foreground {
                        koiPondClockFaces(in: clocks, stacked: plan.stackedClocks, direction: .rightToLeft)
                        if analyze {
                            RoundedRectangle(cornerRadius: 12).fill(SurroundTheme.koiPond.panel)
                                .frame(width: tree.width, height: tree.height).position(x: tree.midX, y: tree.midY)
                        }
                    }
                }
            }
            let painted = try sample(foreground: true), water = try sample(foreground: false)
            let label = analyze ? "RTL Analyze tree corner" : "RTL stacked clock seam"
            let exposed = try koiPondChangedPixels(painted, in: gap)
            let underFace = try koiPondChangedPixels(water, in: interior)
            let covered = try koiPondChangedPixels(painted, in: interior)
            XCTAssertGreaterThan(exposed, analyze ? 3 : 10, label)
            XCTAssertGreaterThan(underFace, 3, "The koi must also pass behind the adjacent foreground")
            XCTAssertEqual(covered, 0, "Only the opaque face covers that part of the koi")
            let counts = XCTAttachment(string: "Water gap: \(exposed). Adjacent pond layer: \(underFace). Adjacent foreground: \(covered).")
            counts.name = "\(label) - Changed pixels"
            counts.lifetime = .keepAlways
            add(counts)
            for (phase, image) in [("Clear", painted.clear), ("Passing", painted.fish), ("Pond layer", water.fish)] {
                let attachment = XCTAttachment(image: image)
                attachment.name = "\(label) - \(phase)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    @MainActor
    func testKoiPondSecondaryBoardsShowFishThroughDetailedGlassOnly() throws {
        let bounds = CGRect(x: 116, y: 185, width: 144, height: 144)
        let probe = CGRect(x: 155, y: 233, width: 66, height: 35)
        let appearance = KoiPondBoard.appearance(for: .light)
        let tint = try XCTUnwrap(appearance.waterGlass)
        for reduceTransparency in [false, true] {
            let face = BoardSceneShadowRegion(bounds: bounds, isDetailed: true, cellSize: 16)
            let pair = try koiPondCrossing(in: probe, reservations: [], secondary: face) {
                KoiPondGlassFace(tint: tint, opaqueColor: appearance.surfaceColor(detailed: false), surfaceIsInScene: true,
                                 cellSize: 16, cornerRadius: 4, reduceTransparency: reduceTransparency)
                    .frame(width: bounds.width, height: bounds.height).position(x: bounds.midX, y: bounds.midY)
            }
            let changed = try koiPondChangedPixels(pair, in: probe)
            if reduceTransparency { XCTAssertEqual(changed, 0, "The native Reduce Transparency face occludes the passing fish") }
            else { XCTAssertGreaterThan(changed, 80, "A secondary glass board must let the passing fish show through") }
        }
    }

    @MainActor
    func testKoiPondNativeRenderingFollowsTheStrokeAndGlidePose() throws {
        let window = CGRect(x: 0, y: 0, width: 440, height: 956)
        let board = CGRect(x: 0, y: 285, width: 440, height: 440)
        let routes = KoiPondSwimSchool(seed: 31).routes(in: window, gameArea: window, board: board,
                                                       detailed: true, avoiding: [])
        for route in routes {
            var sawStroke = false, sawGlide = false
            for index in 0...1000 {
                let time = Double(index) * 0.15, pose = route.pose(at: time)
                let stroke = pose.tailAmplitude > 0.72, glide = pose.tailAmplitude < 0.02
                guard (stroke && !sawStroke) || (glide && !sawGlide), window.contains(route.bounds(at: time)) else { continue }
                let side = ceil(route.length * 1.5)
                func pixels(amplitude: CGFloat?) throws -> [UInt8] {
                    let fish = Canvas { context, _ in
                        var world = context
                        world.translateBy(x: side * 0.5 - pose.center.x, y: side * 0.5 - pose.center.y)
                        if let amplitude {
                            KoiPondSwimmer.draw(in: world, asset: route.assetName, center: pose.center, length: route.length,
                                                heading: pose.heading, tailPhase: pose.beat, amplitude: amplitude,
                                                bend: pose.bend, opacity: route.opacity)
                        } else {
                            KoiPondSwimmer.draw(in: world, route: route, at: time)
                        }
                    }.frame(width: side, height: side)
                    return try nativeMaterialPixels(fish, scale: 1).pixels
                }
                let actual = try pixels(amplitude: nil), expected = try pixels(amplitude: pose.tailAmplitude)
                XCTAssertTrue(actual == expected, "The visible artwork must use this koi's instantaneous tail motion")
                let opposite = try pixels(amplitude: stroke ? 0 : 1)
                let changed = zip(actual, opposite).filter { abs(Int($0) - Int($1)) > 8 }.count
                XCTAssertGreaterThan(changed, 20, "A continuing tail stroke must visibly differ from a settled glide")
                sawStroke = sawStroke || stroke
                sawGlide = sawGlide || glide
                if sawStroke && sawGlide { break }
            }
            XCTAssertTrue(sawGlide && sawStroke, "Sample both poses while the packaged fish is fully visible")
        }
    }

    @MainActor
    func testKoiPondForwardGlidesAlignTheTailAndKeepVisibleStrokes() throws {
        let side: CGFloat = 160, length: CGFloat = 105, scale: CGFloat = 2
        for asset in ["KoiPondKohaku", "KoiPondSanke", "KoiPondGold"] {
            func offsets(effort: CGFloat, phase: Double) throws -> (trunk: CGFloat, stalk: CGFloat, tail: CGFloat) {
                let fish = Canvas { context, _ in
                    KoiPondSwimmer.draw(in: context, asset: asset, center: CGPoint(x: side / 2, y: side / 2),
                                        length: length, heading: 0, tailPhase: phase, amplitude: effort, bend: 0)
                }.frame(width: side, height: side)
                let image = try nativeMaterialPixels(fish, scale: scale)
                // The fish faces right. Take the alpha-weighted center across a slice of its
                // length so a long, translucent fin lobe cannot stand in for the whole tail.
                func centerline(_ slice: ClosedRange<CGFloat>) throws -> CGFloat {
                    let noseX = (side + length) * scale / 2
                    let first = Int((noseX - slice.upperBound * length * scale).rounded())
                    let last = Int((noseX - slice.lowerBound * length * scale).rounded())
                    var mass = 0, moment = 0
                    for y in 0..<image.height {
                        for x in first..<last {
                            let alpha = Int(image.pixels[(y * image.width + x) * 4 + 3])
                            mass += alpha
                            moment += y * alpha
                        }
                    }
                    let center = try XCTUnwrap(mass > 0 ? CGFloat(moment) / CGFloat(mass) : nil,
                                               "\(asset) must paint the sampled body section")
                    return center / (length * scale)
                }
                let head = try centerline(0.10...0.20)
                return try (centerline(0.57...0.63) - head, centerline(0.72...0.78) - head,
                            centerline(0.88...0.94) - head)
            }
            let glide = try offsets(effort: 0, phase: 0)
            XCTAssertEqual(glide.trunk, 0, accuracy: 0.05, "\(asset) arches its body on a forward glide")
            XCTAssertEqual(glide.stalk, 0, accuracy: 0.05, "\(asset) bends sideways before the tail on a forward glide")
            XCTAssertEqual(glide.tail, 0, accuracy: 0.04, "\(asset) carries its tail off the head axis on a forward glide")
            let strokes = try (0..<4).map { try offsets(effort: 1, phase: Double($0) * .pi / 2).tail }
            let first = try XCTUnwrap(strokes.min()), last = try XCTUnwrap(strokes.max())
            XCTAssertGreaterThan(last - first, 0.10, "\(asset) must still sweep its tail through a visible stroke")
        }
    }

    @MainActor
    func testKoiPondSankeKeepsBothTailLobesTrailingInAGlide() throws {
        let length: CGFloat = 105, scale: CGFloat = 3
        let center = CGPoint(x: 80, y: 48)
        let fish = Canvas { context, _ in
            KoiPondSwimmer.draw(in: context, asset: "KoiPondSanke", center: center,
                                length: length, heading: 0, tailPhase: 0, amplitude: 0, bend: 0)
        }.frame(width: 160, height: 96)
        let image = try nativeMaterialPixels(fish, scale: scale)
        // From the tip to the stalk, count consecutive slices where both lobes
        // are visible on opposite sides of the notch. Either lobe can be longer.
        let tip = Int((center.x - 0.50 * length) * scale)
        let stalk = Int((center.x - 0.30 * length) * scale)
        let splitFin = (tip..<stalk).map { x in
            let visible = (0..<image.height).map { y in image.pixels[(y * image.width + x) * 4 + 3] > 40 }
            return visible.split(separator: false).filter { $0.count >= Int(scale) }.count >= 2
        }
        let forkLength = splitFin.split(separator: false).map(\.count).max() ?? 0
        XCTAssertGreaterThan(CGFloat(forkLength) / scale, 0.03 * length,
                             "Both lobes of the Sanke's tail must trail behind their shared fork")
    }

    @MainActor
    func testKoiPondSlowSwimBoundsContainThePaintedKoiAndFlexedTail() throws {
        let school = KoiPondSwimSchool(seed: 54)
        let phone = CGRect(x: 0, y: 0, width: 440, height: 956)
        let phoneFish = school.routes(in: phone, gameArea: phone,
                                      board: CGRect(x: 0, y: 285, width: 440, height: 440), detailed: true, avoiding: [])
        let narrowFish = school.routes(in: CGRect(x: 0, y: 0, width: 220, height: 370),
                                       gameArea: CGRect(x: 0, y: 24, width: 220, height: 316),
                                       board: CGRect(x: 0, y: 88, width: 220, height: 192), detailed: true,
                                       avoiding: [CGRect(x: 0, y: 24, width: 220, height: 53),
                                                  CGRect(x: 0, y: 280, width: 220, height: 32)])
        let narrowExterior = narrowFish.filter { !$0.submerged }
        XCTAssertEqual(Set(phoneFish.map(\.assetName)), ["KoiPondGold", "KoiPondSanke", "KoiPondKohaku"])
        XCTAssertFalse(narrowExterior.isEmpty)
        for route in phoneFish + narrowExterior {
            for sample in 0..<8 {
                let time = Double(sample) * (route.duration > 0 ? route.duration / 8 : 0.3)
                let pose = route.pose(at: time), bounds = route.bounds(at: time)
                let side = ceil(max(bounds.width, bounds.height)) + 24
                let center = CGPoint(x: side / 2, y: side / 2)
                let fish = Canvas { context, _ in
                    KoiPondSwimmer.draw(in: context, asset: route.assetName, center: center,
                                        length: route.length, heading: pose.heading, tailPhase: pose.beat,
                                        amplitude: pose.tailAmplitude, bend: pose.bend)
                }.frame(width: side, height: side)
                let image = try nativeMaterialPixels(fish, scale: 1)
                var painted = CGRect.null
                for offset in stride(from: 3, to: image.pixels.count, by: 4) where image.pixels[offset] > 16 {
                    let pixel = offset / 4
                    painted = painted.union(CGRect(x: pixel % image.width, y: pixel / image.width, width: 1, height: 1))
                }
                let expected = bounds.offsetBy(dx: center.x - pose.center.x, dy: center.y - pose.center.y)
                XCTAssertFalse(painted.isNull, "The native renderer must paint \(route.assetName)")
                XCTAssertTrue(expected.insetBy(dx: -1, dy: -1).contains(painted),
                              "\(route.assetName) extends beyond its reserved body and tail at \(time) seconds")
            }
        }
    }

    @MainActor
    func testKoiPondGlassShowsTheSceneAndSuppliesWaterForIsolatedBoards() throws {
        for scheme: ColorScheme in [.light, .dark] {
            let board = KoiPondBoard.appearance(for: scheme)
            let tint = try XCTUnwrap(board.waterGlass)
            func centerAlpha(scene: Bool, reduceTransparency: Bool = false) throws -> UInt8 {
                let pane = KoiPondGlassFace(tint: tint, opaqueColor: board.surfaceColor(detailed: false),
                                            surfaceIsInScene: scene, cellSize: 22, cornerRadius: 0,
                                            reduceTransparency: reduceTransparency)
                    .frame(width: 90, height: 120)
                    .environment(\.colorScheme, scheme)
                let image = try nativeMaterialPixels(pane, scale: 1)
                return image.pixels[((image.height / 2) * image.width + image.width / 2) * 4 + 3]
            }
            let glass = try centerAlpha(scene: true)
            XCTAssertGreaterThan(glass, 0, "The pane tints the water")
            XCTAssertLessThan(glass, 220, "The scene's submerged koi remain visible")
            XCTAssertEqual(try centerAlpha(scene: false), 255, "Standalone boards supply their own pond")
            XCTAssertEqual(try centerAlpha(scene: true, reduceTransparency: true), 255,
                           "Reduce Transparency uses the legible solid pond color")
        }
    }

    @MainActor
    func testKoiPondSubmergedPairFollowsTheBoardAcrossLayouts() throws {
        for landscape in [false, true] {
            let size = landscape ? CGSize(width: 320, height: 152) : CGSize(width: 152, height: 320)
            var preceding: [UInt8]?
            for offset: CGFloat in [20, 172] {
                let face = CGRect(x: landscape ? offset : 20, y: landscape ? 20 : offset, width: 112, height: 112)
                func render(detailed: Bool) throws -> [UInt8] {
                    let region = BoardSceneShadowRegion(bounds: face, isDetailed: detailed, cellSize: detailed ? 16 : 7)
                    let scene = GameDetailBackdrop(sceneBoards: [region])
                        .environment(\.surroundTheme, .koiPond)
                        .environment(\.colorScheme, .light)
                        .frame(width: size.width, height: size.height)
                    return try nativeMaterialPixels(scene, scale: 1).pixels
                }
                let opened = try render(detailed: true)
                let compact = try render(detailed: false)
                var firstKoi = 0, secondKoi = 0, outside = 0, bankChanges = 0
                let width = Int(size.width)
                for y in 0..<Int(size.height) {
                    for x in 0..<width {
                        let i = 4 * (y * width + x)
                        if let preceding, x < 12, y < 12, preceding[i..<(i+3)] != opened[i..<(i+3)] {
                            bankChanges += 1
                        }
                        let changed = (0..<3).contains { abs(Int(opened[i + $0]) - Int(compact[i + $0])) > 5 }
                        guard changed else { continue }
                        let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                        if !face.contains(point) { outside += 1 }
                        else if point.x < face.midX { firstKoi += 1 }
                        else { secondKoi += 1 }
                    }
                }
                XCTAssertGreaterThan(firstKoi, 65, "The red and white koi follows the board's left half")
                XCTAssertGreaterThan(secondKoi, 65, "The gold koi follows the board's right half")
                XCTAssertEqual(outside, 0, "Only the submerged pair changes at the compact cutoff")
                XCTAssertEqual(bankChanges, 0, "The bank stays anchored to the window when the board moves")
                preceding = opened
            }
        }
    }

    @MainActor
    func testKoiPondOuterPairFitsBesideTheCornerControls() throws {
        // Upper-right space beside the opponent chip; lower-left space beside
        // the actions. A full-width clock and another pane occupy the rest.
        let game = CGRect(x: 22, y: 28, width: 156, height: 249)
        let face = CGRect(x: 22, y: 118, width: 156, height: 115)
        let panels = [CGRect(x: 22, y: 28, width: 156, height: 53),
                      CGRect(x: 22, y: 81, width: 74, height: 37),
                      CGRect(x: 101, y: 233, width: 77, height: 44)]
        let above = CGRect(x: 96, y: 81, width: 82, height: 37)
        let below = CGRect(x: 22, y: 233, width: 79, height: 44)
        func render(_ controls: [CGRect]) throws -> [UInt8] {
            let scene = KoiPondScene(scheme: .light, boards: [BoardSceneShadowRegion(bounds: face)],
                                     gameArea: game, controlReservations: controls).frame(width: 200, height: 300)
            return try nativeMaterialPixels(scene, scale: 1).pixels
        }
        let occupied = try render([game]), open = try render(panels)
        var upperFish = 0, lowerFish = 0, clippedOrCovered = 0
        for y in 0..<300 {
            for x in 0..<200 {
                let i = 4 * (y * 200 + x)
                let changed = (0..<3).contains { abs(Int(open[i + $0]) - Int(occupied[i + $0])) > 5 }
                guard changed else { continue }
                let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                if above.contains(point) { upperFish += 1 }
                else if below.contains(point) { lowerFish += 1 }
                else { clippedOrCovered += 1 }
            }
        }
        XCTAssertGreaterThan(upperFish, 65)
        XCTAssertGreaterThan(lowerFish, 65)
        XCTAssertEqual(clippedOrCovered, 0, "Both fish should fit in the exposed water")
    }

    @MainActor
    func testKoiPondOuterFishUseTheExposedRailWhenTheGameAreaIsFull() throws {
        let window = CGRect(x: 0, y: 0, width: 240, height: 360)
        let content = CGRect(x: 0, y: 0, width: 196, height: 360)
        let board = BoardSceneShadowRegion(bounds: CGRect(x: 10, y: 175, width: 176, height: 176))
        func render(_ gameArea: CGRect) throws -> [UInt8] {
            try nativeMaterialPixels(KoiPondScene(scheme: .light, boards: [board], gameArea: gameArea,
                                                 controlReservations: [gameArea]).frame(width: 240, height: 360),
                                     scale: 1).pixels
        }
        let rail = try render(content), noRail = try render(window)
        var upper = 0, lower = 0, outside = 0
        for y in 0..<360 {
            for x in 0..<240 {
                let i = 4 * (y * 240 + x)
                guard (0..<3).contains(where: { abs(Int(rail[i + $0]) - Int(noRail[i + $0])) > 5 })
                else { continue }
                if x >= 196, (211..<265).contains(y) { upper += 1 }
                else if x >= 196, (265..<319).contains(y) { lower += 1 }
                else { outside += 1 }
            }
        }
        XCTAssertGreaterThan(upper, 120)
        XCTAssertGreaterThan(lower, 120)
        XCTAssertEqual(outside, 0, "Leave the board, status tray and lower rail button clear")
    }

    @MainActor
    func testKoiPondFitsBothExteriorFishBelowASmallScoringBoard() throws {
        let content = CGRect(x: 0, y: 24, width: 220, height: 316)
        // Eleven points between the cards and board leave seven after their two-point clearances.
        let face = CGRect(x: 0, y: 88, width: 220, height: 192)
        let scoreCards = CGRect(x: 0, y: 24, width: 220, height: 53)
        let actions = CGRect(x: 0, y: 280, width: 220, height: 32)
        func render(controls: [CGRect]) throws -> [UInt8] {
            let scene = KoiPondScene(scheme: .light, boards: [BoardSceneShadowRegion(bounds: face)],
                                     gameArea: content, controlReservations: controls).frame(width: 220, height: 370)
            return try nativeMaterialPixels(scene, scale: 1).pixels
        }
        let closed = try render(controls: [content]), open = try render(controls: [scoreCards, actions])
        var left = 0, right = 0, elsewhere = 0
        for y in 0..<370 {
            for x in 0..<220 {
                let i = 4 * (y * 220 + x)
                guard (0..<3).contains(where: { abs(Int(open[i + $0]) - Int(closed[i + $0])) > 5 })
                else { continue }
                if !(312..<340).contains(y) { elsewhere += 1 }
                else if x < 110 { left += 1 }
                else { right += 1 }
            }
        }
        XCTAssertGreaterThan(left, 120)
        XCTAssertGreaterThan(right, 120)
        XCTAssertEqual(elsewhere, 0, "The seven-point gap above the board is too shallow for a recognizable koi")
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

    func testFrostPineShadowProjectsDownRightAndReachesGameplay() {
        for size in [CGSize(width: 320, height: 568), CGSize(width: 402, height: 874),
                     CGSize(width: 874, height: 402), CGSize(width: 820, height: 1180),
                     CGSize(width: 1180, height: 820), CGSize(width: 2500, height: 1500)] {
            let shadow = FrostPineShadowLayout(size: size)
            let pine = FrostPineDecorationLayout(size: size).pine
            XCTAssertGreaterThan(shadow.canopy.width, pine.width)
            XCTAssertGreaterThan(shadow.canopy.midX, pine.midX,
                                 "The upper-left light casts toward the right")
            XCTAssertGreaterThan(shadow.canopy.midY, pine.midY)
            XCTAssertFalse(shadow.canopy.intersection(CGRect(origin: .zero, size: size)).isEmpty)
            XCTAssertLessThanOrEqual(shadow.canopy.width, 840)
            XCTAssertGreaterThan(shadow.blurRadius, 0)
            XCTAssertLessThanOrEqual(shadow.blurRadius, 5)
            XCTAssertGreaterThan(shadow.topFadeHeight, 0)
            XCTAssertLessThanOrEqual(shadow.topFadeHeight, 92)
        }
        let phone = FrostPineShadowLayout(size: CGSize(width: 402, height: 874))
        XCTAssertTrue(phone.canopy.contains(CGPoint(x: 200, y: 350)),
                      "The projected canopy must reach the portrait board, not just the ornament")
        XCTAssertTrue(phone.canopy.contains(CGPoint(x: 180, y: 180)),
                      "The upper player and clock area also receives the cast")
        let landscape = FrostPineShadowLayout(size: CGSize(width: 874, height: 402))
        XCTAssertTrue(landscape.canopy.contains(CGPoint(x: 440, y: 180)))
        let tablet = FrostPineShadowLayout(size: CGSize(width: 820, height: 1180))
        XCTAssertTrue(tablet.canopy.contains(CGPoint(x: 450, y: 450)))
    }

    func testFrostPineShadowResizesContinuouslyAndHandlesInvalidViewports() {
        func metrics(_ layout: FrostPineShadowLayout) -> [CGFloat] {
            [layout.size.width, layout.size.height, layout.canopy.minX, layout.canopy.minY,
             layout.canopy.width, layout.canopy.height, layout.blurRadius, layout.topFadeHeight]
        }
        let sweeps = [(300...1600).map { CGSize(width: CGFloat($0), height: 600) },
                      (300...1600).map { CGSize(width: 900, height: CGFloat($0)) }]
        for sizes in sweeps {
            let layouts = sizes.map { FrostPineShadowLayout(size: $0) }
            for (before, after) in zip(layouts, layouts.dropFirst()) {
                for (a, b) in zip(metrics(before), metrics(after)) {
                    XCTAssertLessThanOrEqual(abs(b - a), 1.5,
                                             "A one-point resize cannot jump the viewport-anchored shadow")
                }
            }
        }
        for size in [CGSize.zero, CGSize(width: 0, height: 320), CGSize(width: -10, height: 400),
                     CGSize(width: CGFloat.infinity, height: 400), CGSize(width: 400, height: CGFloat.nan)] {
            let layout = FrostPineShadowLayout(size: size)
            XCTAssertTrue(metrics(layout).allSatisfy { $0.isFinite && $0 >= 0 })
            XCTAssertEqual(layout.canopy.size, .zero)
            XCTAssertEqual(layout.blurRadius, 0)
        }
    }

    @MainActor
    func testFrostPineShadowMaskUnionsBoardExclusionsAndProtectsTopChrome() throws {
        let holes = [CGRect(x: 20, y: 40, width: 70, height: 50),
                     CGRect(x: 70, y: 60, width: 60, height: 40),
                     CGRect(x: -8, y: 90, width: 20, height: 35)]
        let size = CGSize(width: 160, height: 120)
        let raster = try nativeMaterialPixels(Color.black
            .mask(FrostPineShadowMask(excludedBoards: holes.map { BoardSceneShadowRegion(bounds: $0) }, topFadeHeight: 24))
            .frame(width: size.width, height: size.height))
        func alpha(_ x: Int, _ y: Int) -> UInt8 { raster.pixels[(y * raster.width + x) * 4 + 3] }
        var holesAreClear = true
        var fieldIsOpaque = true
        for y in 0..<raster.height {
            for x in 0..<raster.width {
                let point = CGPoint(x: (CGFloat(x) + 0.5) / 3, y: (CGFloat(y) + 0.5) / 3)
                // Keep a device-pixel margin around rasterized rectangle edges.
                if holes.contains(where: { $0.insetBy(dx: 1.0 / 3, dy: 1.0 / 3).contains(point) }) {
                    holesAreClear = holesAreClear && alpha(x, y) == 0
                } else if point.y > 25 && !holes.contains(where: {
                    $0.insetBy(dx: -1.0 / 3, dy: -1.0 / 3).contains(point)
                }) {
                    fieldIsOpaque = fieldIsOpaque && alpha(x, y) == 255
                }
            }
        }
        XCTAssertTrue(holesAreClear, "Overlapping boards must never expose the shadow again")
        XCTAssertTrue(fieldIsOpaque, "Protecting boards must retain cast over other game elements")
        XCTAssertLessThan(alpha(450, 1), 10, "The title's upper edge remains clear of the cast")
        XCTAssertGreaterThan(alpha(450, 36), alpha(450, 1))
        XCTAssertLessThan(alpha(450, 36), 200, "Chrome protection fades gradually, without a hard stripe")
        let empty = try nativeMaterialPixels(Color.black.mask(FrostPineShadowMask())
            .frame(width: size.width, height: size.height))
        XCTAssertTrue(stride(from: 3, to: empty.pixels.count, by: 4).allSatisfy { empty.pixels[$0] == 255 },
                      "An empty exclusion list leaves the complete silhouette available")
    }

    @MainActor
    func testBoardSceneShadowAnchorsProtectAllOptedInBoards() throws {
        // BoardView attaches this production modifier to the visible slab.
        // Exercise the real preference, coordinate conversion and mask with
        // synthetic white content, independently of the theme's image assets.
        let cases: [(name: String, board: CGSize, origin: CGPoint, scene: CGSize, radius: CGFloat)] = [
            ("compact", CGSize(width: 63, height: 63), CGPoint(x: 10, y: 10), CGSize(width: 83, height: 83), 0),
            ("phone", CGSize(width: 180, height: 180), CGPoint(x: 12, y: 16), CGSize(width: 210, height: 220), 0),
            ("iPad", CGSize(width: 360, height: 360), CGPoint(x: 20, y: 20), CGSize(width: 400, height: 400), 0),
            ("offset rectangle", CGSize(width: 120, height: 75), CGPoint(x: 22, y: 11), CGSize(width: 170, height: 110), 0),
            ("rounded slab with shadow reserve", CGSize(width: 120, height: 130), CGPoint(x: 14, y: 12), CGSize(width: 154, height: 160), 18),
            ("cropped rounded preview", CGSize(width: 240, height: 180), CGPoint(x: 22, y: 22), CGSize(width: 100, height: 100), 18)
        ]
        func render(board: CGSize, origin: CGPoint, scene: CGSize, radius: CGFloat, enabled: Bool?) throws
            -> (pixels: [UInt8], width: Int, height: Int) {
            let content = ZStack(alignment: .topLeading) {
                Color.clear
                RoundedRectangle(cornerRadius: radius, style: .circular).fill(.white)
                    .frame(width: board.width, height: board.height)
                    .modifier(BoardSceneShadowExclusion(cornerRadius: radius))
                    .offset(x: origin.x, y: origin.y)
            }
            .frame(width: scene.width, height: scene.height, alignment: .topLeading)
            .overlayPreferenceValue(BoardSceneShadowExclusionKey.self) { anchors in
                GeometryReader { geometry in
                    Color.black.mask(FrostPineShadowMask(excludedBoards: anchors.map {
                        BoardSceneShadowRegion(bounds: geometry[$0.bounds], cornerRadius: $0.cornerRadius)
                    }))
                }
            }
            .clipped()
            if let enabled {
                return try nativeMaterialPixels(content.environment(\.excludesBoardsFromSceneShadows, enabled))
            }
            return try nativeMaterialPixels(content)
        }
        for fixture in cases {
            let baseline = try render(board: fixture.board, origin: fixture.origin, scene: fixture.scene,
                                      radius: fixture.radius, enabled: nil)
            let disabled = try render(board: fixture.board, origin: fixture.origin, scene: fixture.scene,
                                      radius: fixture.radius, enabled: false)
            XCTAssertEqual(disabled.pixels, baseline.pixels,
                           "Other scenes retain the default no-exclusion behavior: \(fixture.name)")
            XCTAssertTrue(stride(from: 0, to: baseline.pixels.count, by: 4).allSatisfy {
                baseline.pixels[$0] == 0 && baseline.pixels[$0 + 3] == 255
            }, "The default foreground still casts over the complete scene")
            let protected = try render(board: fixture.board, origin: fixture.origin, scene: fixture.scene,
                                       radius: fixture.radius, enabled: true)
            XCTAssertEqual(protected.width, Int(fixture.scene.width * 3))
            XCTAssertEqual(protected.height, Int(fixture.scene.height * 3))
            let boardRect = CGRect(origin: fixture.origin, size: fixture.board)
            // Use geometric distance, not expanded Path.contains, to keep the
            // guard exactly one device pixel around a circular rounded edge.
            let margin: CGFloat = 1.0 / 3
            var boardIsUnshaded = true
            var surroundingCastRemains = true
            var boardPixels = 0
            var surroundingPixels = 0
            var roundedCornerPixels = 0
            var firstUnexpectedCast: String?
            for y in 0..<protected.height {
                for x in 0..<protected.width {
                    let offset = (y * protected.width + x) * 4
                    let point = CGPoint(x: (CGFloat(x) + 0.5) / 3, y: (CGFloat(y) + 0.5) / 3)
                    let qx = abs(point.x - boardRect.midX) - (boardRect.width / 2 - fixture.radius)
                    let qy = abs(point.y - boardRect.midY) - (boardRect.height / 2 - fixture.radius)
                    let distance = hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - fixture.radius
                    if distance < -margin {
                        boardPixels += 1
                        boardIsUnshaded = boardIsUnshaded && (0..<4).allSatisfy { protected.pixels[offset + $0] == 255 }
                    } else if distance > margin {
                        surroundingPixels += 1
                        if boardRect.contains(point) { roundedCornerPixels += 1 }
                        let unchangedCast = protected.pixels[offset] == 0 && protected.pixels[offset + 1] == 0
                            && protected.pixels[offset + 2] == 0 && protected.pixels[offset + 3] == 255
                        surroundingCastRemains = surroundingCastRemains && unchangedCast
                        if !unchangedCast && firstUnexpectedCast == nil {
                            let rgba = Array(protected.pixels[offset..<(offset + 4)])
                            firstUnexpectedCast = "(\(x),\(y)) rgba=\(rgba), distance=\(distance) pt"
                        }
                    }
                }
            }
            XCTAssertGreaterThan(boardPixels, 0)
            XCTAssertGreaterThan(surroundingPixels, 0)
            if fixture.radius > 0 {
                XCTAssertGreaterThan(roundedCornerPixels, 0, "Verify the corner cutouts, not only the outer rectangle")
            }
            XCTAssertTrue(boardIsUnshaded, "The complete slab keeps its original white: \(fixture.name)")
            XCTAssertTrue(surroundingCastRemains,
                          "Reserved margins and rounded corner cutouts must retain cast: \(fixture.name); "
                          + "first unexpected pixel: \(firstUnexpectedCast ?? "none")")
        }
    }

    @MainActor
    func testFrostPineAppearanceAndAnalysisStayReadable() throws {
        assertAdaptiveColorsFollowRepeatedTraitChanges(.frostPine)
        try assertNightAnalysisMarksRemainReadable(.frostPine)
        let cell: CGFloat = 20
        let scale: CGFloat = 3
        for scheme: ColorScheme in [.light, .dark] {
            let board = SurroundTheme.frostPine.board(for: scheme)
            XCTAssertEqual(board.surfaceColor(detailed: false), Color(themeHex: scheme == .light ? 0xBBC0B9 : 0x9FA9A5))
            XCTAssertEqual(board.white.flat, Color(themeHex: scheme == .light ? 0xF1FAFF : 0xE4EFF6))
            let ink = try XCTUnwrap(board.engravedInk)
            XCTAssertGreaterThanOrEqual(contrast(ink.grid, board.boardColor), 3)
            XCTAssertGreaterThanOrEqual(contrast(ink.coordinates, board.boardColor), 4.5)
            let texture = try XCTUnwrap(board.boardTexture)
            let diameter = cell - 2 * board.stonePadding(at: cell)
            let image = try nativeMaterialPixels(board.surfaceColor(detailed: true)
                .overlay {
                    Image(uiImage: texture.image).resizable().colorMultiply(texture.tint)
                        .frame(width: cell * 19, height: cell * 19)
                        .modifier(BoardTextureVisibility(opacity: texture.opacity, cellSize: cell))
                }
                .frame(width: cell * 2, height: cell * 2).clipped()
                .overlay {
                    Stone(color: .white, shadowRadius: 1).frame(width: diameter, height: diameter)
                }
                .environment(\.boardAppearance, board)
                .environment(\.colorScheme, scheme)
                .environment(\.displayScale, scale), scale: scale)
            func patch(offset: CGFloat) -> Double {
                let x = image.width / 2 + Int(offset * cell * scale)
                let y = image.height / 2 + Int(offset * cell * scale)
                let radius = Int(cell * scale * 0.15)
                var sum = 0.0
                for row in y - radius ... y + radius {
                    for column in x - radius ... x + radius {
                        let i = (row * image.width + column) * 4
                        sum += luminance(Color(.sRGB, red: Double(image.pixels[i]) / 255,
                                               green: Double(image.pixels[i + 1]) / 255,
                                               blue: Double(image.pixels[i + 2]) / 255))
                    }
                }
                return sum / Double((2 * radius + 1) * (2 * radius + 1))
            }
            // The diagonal half-cell samples bare ice beyond the stone shadow.
            XCTAssertGreaterThan((patch(offset: 0) + 0.05) / (patch(offset: 0.5) + 0.05), 1.7,
                                 "The pale stone's center stays lighter than the adjacent detailed board in \(scheme)")
        }
    }

    func testFrostPineStoneGradesLiftPaleFacesAndPreserveSilhouettes() throws {
        let theme = SurroundTheme.frostPine
        let night = try XCTUnwrap(theme.board(for: .dark).stoneImages)
        let day = try XCTUnwrap(theme.board(for: .light).stoneImages)
        XCTAssertEqual(day.tint, .white)
        XCTAssertEqual(night.tint, Color(themeHex: 0xD5E2EE))
        let bundle = Bundle(for: SurroundThemeTests.self)
        for (family, dayImages, nightImages) in [("FrostPineMidnight", day.black, night.black),
                                                 ("FrostPinePale", day.white, night.white)] {
            XCTAssertEqual(dayImages.count, 4)
            XCTAssertEqual(nightImages.count, 4)
            for index in 0..<min(dayImages.count, nightImages.count) {
                let original = try XCTUnwrap(UIImage(named: "\(family)\(index)", in: bundle, compatibleWith: nil))
                let source = try XCTUnwrap(original.cgImage)
                let light = try XCTUnwrap(dayImages[index].cgImage)
                let dark = try XCTUnwrap(nightImages[index].cgImage)
                XCTAssertEqual(light.width, source.width)
                XCTAssertEqual(light.height, source.height)
                let before = try rgbaPixels(for: source, side: source.width)
                func brightness(_ pixels: [UInt8], at offset: Int) -> Double {
                    0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1])
                        + 0.0722 * Double(pixels[offset + 2])
                }
                let isPale = family == "FrostPinePale"
                let center = source.width / 3 ..< 2 * source.width / 3
                let sample = stride(from: 0, to: before.count, by: 4).filter { offset in
                    if isPale {
                        let pixel = offset / 4
                        return center.contains(pixel % source.width) && center.contains(pixel / source.width)
                    }
                    return before[offset + 3] == 255 && (20...220).contains(brightness(before, at: offset))
                }
                XCTAssertGreaterThan(sample.count, 1000)
                for (image, isNight) in [(light, false), (dark, true)] {
                    let after = try rgbaPixels(for: image, side: source.width)
                    if isNight && !isPale {
                        XCTAssertEqual(after, before, "Midnight ice keeps its original night artwork")
                        continue
                    }
                    XCTAssertTrue(stride(from: 3, to: before.count, by: 4).allSatisfy { after[$0] == before[$0] },
                                  "Grading preserves the stone's silhouette and internal opacity")
                    let lift = sample.reduce(0.0) {
                        $0 + brightness(after, at: $1) - brightness(before, at: $1)
                    } / Double(sample.count)
                    XCTAssertGreaterThan(lift, 8, "\(family)\(index) needs a visible lift, night=\(isNight)")
                    if isPale {
                        let blueOverRed = sample.reduce(0) { $0 + Int(after[$1 + 2]) - Int(after[$1]) }
                        XCTAssertGreaterThan(Double(blueOverRed) / Double(sample.count), 5,
                                             "The brighter center still reads as blue ice")
                    }
                }
            }
        }
        // Resolving either appearance repeatedly must reuse its own images.
        for scheme: ColorScheme in [.light, .dark, .light, .dark] {
            let resolved = try XCTUnwrap(theme.board(for: scheme).stoneImages)
            let cached = scheme == .light ? day : night
            for (actual, expected) in zip(resolved.black + resolved.white, cached.black + cached.white) {
                XCTAssertTrue(actual === expected)
            }
        }
    }

    func testFrostPineSmallStoneInsetAddsCenteredRoomWithoutChangingCompactBoards() throws {
        let defaults = StoneImages(black: [], white: [])
        for scheme: ColorScheme in [.light, .dark] {
            let images = try XCTUnwrap(SurroundTheme.frostPine.board(for: scheme).stoneImages)
            XCTAssertGreaterThan(images.smallStoneInset, 0)
            for theme in SurroundTheme.allCases where theme != .frostPine && theme != .christmasKeepsakes {
                XCTAssertEqual(theme.board(for: scheme).stoneImages?.smallStoneInset ?? 0, 0,
                               "Only Frost & Pine and Christmas Keepsakes opt into phone stone spacing")
            }
            for cell: CGFloat in [7, 13.99, 14, 14.001, 15, 16, 20, 22, 27, 31.999, 32, 48] {
                let padding: CGFloat = cell < 10 ? 0 : 1
                let nominal = CGRect(x: 3 * cell + padding, y: 5 * cell + padding,
                                     width: cell - 2 * padding, height: cell - 2 * padding)
                let actual = images.displayRect(in: nominal, cellSize: cell)
                XCTAssertEqual(defaults.displayRect(in: nominal, cellSize: cell), nominal)
                XCTAssertEqual(actual.midX, nominal.midX, accuracy: 0.000001)
                XCTAssertEqual(actual.midY, nominal.midY, accuracy: 0.000001)
                XCTAssertEqual(actual.width, actual.height, accuracy: 0.000001)
                XCTAssertTrue(nominal.contains(actual), "Only the visual silhouette may shrink")
                if cell <= 14 || cell >= 32 {
                    XCTAssertEqual(actual, nominal, "Compact and large stones keep their original footprint")
                } else {
                    XCTAssertLessThan(actual.width, nominal.width)
                    XCTAssertLessThan(nominal.width - actual.width, 1,
                                      "Spacing must remain a subtle physical gap, not undersized stones")
                }
                if cell == 14.001 || cell == 31.999 {
                    XCTAssertLessThan(nominal.width - actual.width, 0.001,
                                      "Crossing either end of the size range must not jump the silhouette")
                }
            }
            let left = CGRect(x: 1, y: 1, width: 18, height: 18)
            let right = left.offsetBy(dx: 20, dy: 0)
            let visibleLeft = images.displayRect(in: left, cellSize: 20)
            let visibleRight = images.displayRect(in: right, cellSize: 20)
            let gap = visibleRight.minX - visibleLeft.maxX
            XCTAssertGreaterThan(gap, right.minX - left.maxX + 0.5,
                                 "Neighboring phone stones need a perceptible strip of board between them")
            XCTAssertLessThan(gap, 3)
            XCTAssertEqual(visibleRight.midX - visibleLeft.midX, 20, accuracy: 0.000001,
                           "Playing intersections and marker centers remain fixed")
            let halfGrown = images.displayRect(in: CGRect(x: 1, y: 1, width: 13, height: 13), cellSize: 15)
            let grown = images.displayRect(in: CGRect(x: 1, y: 1, width: 14, height: 14), cellSize: 16)
            XCTAssertGreaterThan(halfGrown.minX, 1)
            XCTAssertLessThan(halfGrown.minX, grown.minX)
            let fading = images.displayRect(in: CGRect(x: 1, y: 1, width: 25, height: 25), cellSize: 27)
            XCTAssertGreaterThan(fading.minX, 1)
            XCTAssertLessThan(fading.minX, visibleLeft.minX)
        }
    }

    @MainActor
    func testFrostPineIceEdgesPreserveFacesSilhouettesAndFlatStones() throws {
        for scheme: ColorScheme in [.light, .dark] {
            let board = SurroundTheme.frostPine.board(for: scheme)
            XCTAssertEqual(board.imageStoneShading, .iceEdge)
            let images = try XCTUnwrap(board.stoneImages)
            XCTAssertFalse(images.black.isEmpty)
            XCTAssertFalse(images.white.isEmpty)
            for color: StoneColor in [.black, .white] {
                for (diameter, shadow): (CGFloat, CGFloat) in [(7, 1), (13.99, 1), (14, 1),
                                                               (20, 0), (20, 1), (28, 1), (32, 1), (44, 1)] {
                    func render(_ shading: ImageStoneShading) throws -> (pixels: [UInt8], width: Int, height: Int) {
                        var appearance = board
                        appearance.imageStoneShading = shading
                        return try nativeMaterialPixels(Stone(color: color, shadowRadius: shadow)
                            .frame(width: diameter, height: diameter).padding(3)
                            .environment(\.boardAppearance, appearance)
                            .environment(\.colorScheme, scheme))
                    }
                    let actual = try render(.iceEdge), plain = try render(.artwork)
                    let detail = "\(scheme) \(color), diameter \(diameter), shadow \(shadow)"
                    XCTAssertEqual(actual.width, plain.width, detail)
                    XCTAssertEqual(actual.height, plain.height, detail)
                    if diameter < 14 || diameter >= 32 || shadow == 0 {
                        XCTAssertEqual(actual.pixels, plain.pixels,
                                       "Flat and large stones retain their original rendering: \(detail)")
                        continue
                    }
                    XCTAssertGreaterThan(zip(actual.pixels, plain.pixels).filter { $0 != $1 }.count, 10,
                                         "Both phone-size ice colors need a visible contour: \(detail)")
                    let midX = Double(actual.width) / 2, midY = Double(actual.height) / 2
                    let visible = images.displayRect(in: CGRect(x: 0, y: 0, width: diameter, height: diameter),
                                                     cellSize: diameter)
                    let radius = Double(visible.width) * 3 / 2
                    var maximumCenterDelta = 0, maximumExteriorDelta = 0, maximumAlphaDelta = 0
                    for y in 0..<actual.height {
                        for x in 0..<actual.width {
                            let offset = (y * actual.width + x) * 4
                            let distance = hypot(Double(x) + 0.5 - midX, Double(y) + 0.5 - midY)
                            if abs(distance - radius) > 2 {
                                maximumAlphaDelta = max(maximumAlphaDelta,
                                    abs(Int(actual.pixels[offset + 3]) - Int(plain.pixels[offset + 3])))
                            }
                            for channel in 0..<4 {
                                let delta = abs(Int(actual.pixels[offset + channel]) - Int(plain.pixels[offset + channel]))
                                if distance < radius * 0.65 {
                                    maximumCenterDelta = max(maximumCenterDelta, delta)
                                }
                                // Exclude the rasterized boundary's subpixel fringe;
                                // beyond it, neither silhouette nor cast may grow.
                                if distance > radius + 2 {
                                    maximumExteriorDelta = max(maximumExteriorDelta, delta)
                                }
                            }
                        }
                    }
                    XCTAssertLessThanOrEqual(maximumCenterDelta, 1,
                                             "Preserve the reflected face beneath markers: \(detail)")
                    XCTAssertLessThanOrEqual(maximumExteriorDelta, 1,
                                             "Keep the contour inside the existing silhouette: \(detail)")
                    XCTAssertLessThanOrEqual(maximumAlphaDelta, 1,
                                             "Preserve alpha away from the antialiased boundary: \(detail)")
                }
            }
        }
    }

    func testFrostedBoardRimDoesNotMoveThePlayingSurface() throws {
        for scheme: ColorScheme in [.light, .dark] {
            let frost = try XCTUnwrap(SurroundTheme.frostPine.board(for: scheme).boardDepth)
            for pigment in [frost.upperFace, frost.lowerFace] {
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                XCTAssertTrue(UIColor(pigment).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
                XCTAssertGreaterThan(blue - red, 0.12, "The sidewall carries a visible blue tint")
                XCTAssertGreaterThan(green, red)
                XCTAssertLessThan(green, blue)
                XCTAssertTrue((0.4...0.85).contains(alpha), "The ice remains visible while admitting scene color")
            }
            XCTAssertGreaterThan(luminance(frost.upperFace), luminance(frost.lowerFace))
            // The original 0.8%-deep slab used the standard cut-board layout.
            // Its face bounds still determine the playable points as the ice wall grows.
            var originalDepth = frost
            originalDepth.edgeStyle = .cut
            originalDepth.thicknessRatio = 0.008
            originalDepth.maximumThickness = 5
            for cell: CGFloat in [7, 13, 14, 15, 18, 20, 32, 48] {
                for coordinates in [false, true] {
                    let side = cell * (coordinates ? 20 : 19)
                    func geometry(_ depth: BoardDepth) -> BoardDepthGeometry {
                        BoardDepthGeometry(containerSize: CGSize(width: side, height: side),
                                           boardWidth: 19, boardHeight: 19, showsCoordinates: coordinates,
                                           displayScale: 3, depth: depth)
                    }
                    let soft = geometry(frost)
                    let original = geometry(originalDepth)
                    XCTAssertEqual(soft.faceRect.minX, original.faceRect.minX, accuracy: 0.000001)
                    XCTAssertEqual(soft.faceRect.minY, original.faceRect.minY, accuracy: 0.000001)
                    XCTAssertEqual(soft.faceRect.width, original.faceRect.width, accuracy: 0.000001)
                    XCTAssertEqual(soft.faceRect.height, original.faceRect.height, accuracy: 0.000001)
                    XCTAssertEqual(soft.cellSize, original.cellSize)
                    XCTAssertLessThanOrEqual(soft.cornerRadius, soft.cellSize / 2)
                    if cell > 14 {
                        XCTAssertGreaterThan(soft.thickness, original.thickness * 1.2,
                                             "The visible ice wall gains depth inside the same board slot")
                        XCTAssertLessThan(soft.thickness, original.thickness * 1.5)
                        XCTAssertGreaterThan(soft.cornerRadius, original.cornerRadius)
                    } else {
                        XCTAssertEqual(soft.thickness, 0)
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

    @MainActor
    func testFrostPineRunningHighlightPreservesTheWeatheredClockAndSnow() throws {
        let padding: CGFloat = 8
        let scale: CGFloat = 3
        for size in [CGSize(width: 190, height: 96), CGSize(width: 88, height: 34)] {
            let frame = CGRect(origin: CGPoint(x: padding, y: padding), size: size)
            let textFace = RoundedRectangle(cornerRadius: 7, style: .circular)
                .path(in: frame.insetBy(dx: 5, dy: 5))
            for scheme: ColorScheme in [.light, .dark] {
                var blackEdgeInks: [Set<Data>] = []
                for color: StoneColor in [.black, .white] {
                    func render(_ highlight: FrostPineClockHighlight?) throws -> [UInt8] {
                        try nativeMaterialPixelsUsingDirectContext(FrostPineWoodPlateMaterial(
                            color: color, cornerRadius: 12, role: .clock, compact: size.height == 34,
                            scheme: scheme, reduceTransparency: false, contrast: .standard,
                            highlight: highlight)
                            .frame(width: size.width, height: size.height)
                            .padding(padding)
                            .environment(\.colorScheme, scheme), scale: scale).pixels
                    }

                    let idle = try render(nil)
                    let normal = try render(.running)
                    let warning = try render(.warning)
                    let width = Int((size.width + 2 * padding) * scale)
                    let detail = "\(color), \(scheme), \(size)"
                    XCTAssertTrue(normal != warning, "Time warning changes the edge color: \(detail)")
                    for (state, active) in [normal, warning].enumerated() {
                        // Count perceptible changes, tolerating rasterization at the frayed edge.
                        let changed = stride(from: 0, to: idle.count, by: 4).filter { i in
                            (0..<4).contains { abs(Int(active[i + $0]) - Int(idle[i + $0])) > 12 }
                        }
                        let points = changed.map { i in
                            CGPoint(x: (CGFloat(i / 4 % width) + 0.5) / scale,
                                    y: (CGFloat(i / 4 / width) + 0.5) / scale)
                        }
                        XCTAssertFalse(changed.contains { idle[$0 + 3] < 16 },
                                       "Lighting the wood must preserve its chipped silhouette: \(detail)")
                        XCTAssertTrue(points.allSatisfy { frame.contains($0) && $0.y > frame.minY + 1 },
                                      "Snow above the plate and across its top edge stays clear: \(detail)")
                        XCTAssertFalse(points.contains { textFace.contains($0) },
                                       "The running and warning lights leave the clock face clear: \(detail)")
                        let onSides = points.filter { abs($0.y - frame.midY) < frame.height / 4 }
                        for count in [onSides.filter { $0.x < frame.midX }.count,
                                      onSides.filter { $0.x > frame.midX }.count] {
                            XCTAssertGreaterThan(count, Int(size.height * scale / 2),
                                                 "Both exposed sides carry the highlight: \(detail)")
                        }
                        XCTAssertGreaterThan(points.filter { $0.y > frame.maxY - 5 }.count,
                                             Int(size.width * scale),
                                             "The lower cut carries the highlight: \(detail)")

                        // Below the snow, find the repeated edge pigments on a straight side.
                        // The two cuts of wood have different grain and different chips.
                        let side = changed.filter { i in
                            let y = CGFloat(i / 4 / width) / scale
                            return i / 4 % width < width / 2 && y > frame.midY && y < frame.maxY - 10
                        }
                        let pigments = Dictionary(grouping: side) { i in Data(active[i..<i + 3]) }
                        let repeated = Set(pigments.filter { $0.value.count >= 6 }.keys)
                        if color == .black {
                            blackEdgeInks.append(repeated)
                        } else {
                            XCTAssertGreaterThanOrEqual(blackEdgeInks[state].intersection(repeated).count, 2,
                                                        "Both woods use the same light and shade: \(detail)")
                        }
                        if size.height > 34 {
                            let rows = Dictionary(grouping: side) { $0 / 4 / width }
                            let starts = rows.values.compactMap { $0.first.map { $0 / 4 % width } }
                            XCTAssertGreaterThan(Set(starts).count, 1, "The light follows the rough cut: \(detail)")
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testFrostPineWoodPlatesKeepTextReadableAcrossSizesAndAccessibility() throws {
        _ = try XCTUnwrap(UIImage(named: "FrostPineControlWood", in: Bundle(for: Self.self), compatibleWith: nil),
                          "The material audit must include the bundled pine grain")
        let theme = SurroundTheme.frostPine
        let scale = 3
        let linear = (0...255).map { byte -> Double in
            let value = Double(byte) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let players = [OGSUser(username: "ordinary", id: 1),
                       OGSUser(username: "moderator", id: 2, isModerator: true),
                       OGSUser(username: "professional", id: 3, professional: true),
                       OGSUser(username: "supporter", id: 4, supporter: true),
                       OGSUser(username: "bot", id: 5, isBot: true)]
        let cases: [(name: String, role: FrostPineWoodPlateSurface.Role, size: CGSize,
                     inset: CGSize, radius: CGFloat, compact: Bool, player: Bool)] = [
            ("full clock", .clock, CGSize(width: 190, height: 96), CGSize(width: 12, height: 4), 12, false, false),
            ("narrow clock", .clock, CGSize(width: 104, height: 144), CGSize(width: 10, height: 4), 12, false, false),
            ("inline clock", .clock, CGSize(width: 140, height: 28), CGSize(width: 8, height: 4), 12, true, false),
            ("wide inline clock", .clock, CGSize(width: 320, height: 34), CGSize(width: 8, height: 4), 12, true, false),
            ("row player", .player, CGSize(width: 156, height: 52), CGSize(width: 4, height: 4), 10, false, true),
            ("column player", .player, CGSize(width: 126, height: 84), CGSize(width: 5, height: 5), 9, true, true),
            ("vertical player", .player, CGSize(width: 156, height: 144), CGSize(width: 8, height: 8), 12, false, true),
            ("header player", .player, CGSize(width: 220, height: 44), CGSize(width: 4, height: 8), 10, true, true)
        ]
        let modes: [(name: String, reduced: Bool, contrast: ColorSchemeContrast)] = [
            ("standard", false, .standard),
            ("reduced transparency", true, .standard),
            ("increased contrast", false, .increased)
        ]
        for scheme: ColorScheme in [.light, .dark] {
            let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
            for color: StoneColor in [.black, .white] {
                let identityInks: [(String, Color)] = [
                    ("identity", theme.identityForeground(color)),
                    ("secondary", theme.identitySecondary(color))
                ] + players.map { ($0.username, theme.roleColor(for: $0, on: color)) }
                let clockInks: [(String, Color)] = [
                    ("clock", theme.clockForeground(color, scheme: scheme)),
                    ("accent", theme.clockAccent(color)),
                    ("sudden death", theme.clockSuddenDeathAccent(color, scheme: scheme)),
                    ("agreement", theme.clockAgreementAccent(color, scheme: scheme)),
                    ("disconnected", theme.clockDisconnectedAccent(color, scheme: scheme)),
                    ("undo", theme.clockUndoAccent(color, scheme: scheme))
                ]
                for sample in cases {
                    for mode in modes {
                        let rendered = try nativeMaterialPixels(FrostPineWoodPlateMaterial(
                            color: color, cornerRadius: sample.radius,
                            role: sample.role, compact: sample.compact, scheme: scheme,
                            reduceTransparency: mode.reduced, contrast: mode.contrast)
                            .frame(width: sample.size.width, height: sample.size.height)
                            .environment(\.colorScheme, scheme))
                        let message = "\(sample.name), \(scheme), \(color), \(mode.name)"
                        XCTAssertEqual(rendered.width, Int(sample.size.width) * scale, message)
                        XCTAssertEqual(rendered.height, Int(sample.size.height) * scale, message)
                        // Check the real text reserve rather than the decorative
                        // rim: every frost fragment or grain stroke under a label
                        // must retain its contrast, including the narrow clocks.
                        let textRect = CGRect(origin: .zero, size: sample.size)
                            .insetBy(dx: sample.inset.width, dy: sample.inset.height)
                        // Padding reserves a rounded interior, not the corner
                        // cutouts or their outline. Retain the full straight
                        // bottom reserve, where metadata can reach within 4 pt.
                        let edgeInset = min(sample.inset.width, sample.inset.height)
                        let roundedReserve = RoundedRectangle(cornerRadius: max(0, sample.radius - edgeInset),
                                                              style: .circular)
                            .path(in: CGRect(origin: .zero, size: sample.size)
                                .insetBy(dx: edgeInset, dy: edgeInset))
                        var minimum = Double.infinity, maximum = 0.0
                        var darkestPoint = CGPoint.zero, brightestPoint = CGPoint.zero
                        var minimumAlpha: UInt8 = 255
                        for y in Int(textRect.minY) * scale..<Int(textRect.maxY) * scale {
                            for x in Int(textRect.minX) * scale..<Int(textRect.maxX) * scale {
                                let point = CGPoint(x: (CGFloat(x) + 0.5) / CGFloat(scale),
                                                    y: (CGFloat(y) + 0.5) / CGFloat(scale))
                                guard roundedReserve.contains(point) else { continue }
                                let offset = (y * rendered.width + x) * 4
                                minimumAlpha = min(minimumAlpha, rendered.pixels[offset + 3])
                                let red = linear[Int(rendered.pixels[offset])]
                                let green = linear[Int(rendered.pixels[offset + 1])]
                                let blue = linear[Int(rendered.pixels[offset + 2])]
                                let value = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                                if value < minimum { minimum = value; darkestPoint = point }
                                if value > maximum { maximum = value; brightestPoint = point }
                            }
                        }
                        XCTAssertEqual(minimumAlpha, 255, "The text backing stays opaque: \(message)")
                        for (name, ink) in sample.player ? identityInks : clockInks {
                            let value = luminance(ink, style: style)
                            let nearest = min(maximum, max(minimum, value))
                            XCTAssertGreaterThanOrEqual((max(value, nearest) + 0.05)
                                / (min(value, nearest) + 0.05), 4.5,
                                "\(name): \(message); dark \(minimum) at \(darkestPoint), light \(maximum) at \(brightestPoint)")
                        }
                        if mode.reduced || mode.contrast == .increased {
                            XCTAssertLessThan(maximum - minimum, 0.001,
                                              "Accessibility text backing stays solid: \(message)")
                        }
                    }
                }
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
            let styles: [UIUserInterfaceStyle] = theme.colorScheme.map { [$0 == .dark ? .dark : .light] }
                ?? [.light, .dark]
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
    func testFrostPineCornerPatchCrossesTheLipAndFadesOnTheFrontEdge() throws {
        let scale: CGFloat = 2
        for scheme: ColorScheme in [.light, .dark] {
            let board = SurroundTheme.frostPine.board(for: scheme)
            let frost = try XCTUnwrap(board.surfaceFrost)
            XCTAssertNotNil(frost.lowerLeftDeposit)
            for side: CGFloat in [247, 400] {
                let layout = BoardDepthGeometry(containerSize: CGSize(width: side, height: side),
                                               boardWidth: 19, boardHeight: 19, showsCoordinates: false,
                                               displayScale: scale, depth: board.boardDepth)
                let result = try nativeMaterialPixelsUsingDirectContext(
                    FrostPineCornerDeposit(surface: frost, layout: layout, cornerRadius: layout.cornerRadius)
                        .frame(width: layout.visibleRect.width, height: layout.visibleRect.height)
                        .environment(\.displayScale, scale)
                        .environment(\.colorScheme, scheme), scale: scale)
                func alpha(_ x: Int, _ y: Int) -> UInt8 { result.pixels[(y * result.width + x) * 4 + 3] }
                if layout.cellSize < 14 {
                    XCTAssertTrue(stride(from: 3, to: result.pixels.count, by: 4)
                        .allSatisfy { result.pixels[$0] == 0 }, "Compact ice stays solid in \(scheme)")
                    continue
                }
                let cell = layout.cellSize * scale
                let lip = Int(layout.faceRect.height * scale)
                let cornerWidth = Int(ceil(3 * cell))
                var topPixels = 0, wallPixels = 0, outsidePixels = 0
                for y in 0..<result.height {
                    for x in 0..<result.width where alpha(x, y) > 0 {
                        if x >= cornerWidth || y < lip - Int(ceil(cell)) {
                            outsidePixels += 1
                        } else if alpha(x, y) > 15 {
                            if y < lip { topPixels += 1 } else { wallPixels += 1 }
                        }
                    }
                }
                XCTAssertEqual(outsidePixels, 0, "The remaining front edge and playing field stay clear")
                XCTAssertGreaterThan(topPixels, 20, "Some crystals remain visible on the top in \(scheme)")
                XCTAssertGreaterThan(wallPixels, 12, "The frost reaches the translucent sidewall in \(scheme)")
                let acrossLip = (0..<cornerWidth).filter { alpha($0, lip - 1) > 8 && alpha($0, lip + 1) > 8 }
                XCTAssertGreaterThan(acrossLip.count, 4, "Top and wall share a visible deposit at the lip")
                func wallAlpha(startingAt offset: CGFloat) -> Int {
                    let start = Int(offset * cell)
                    var total = 0
                    for y in (lip + 1)..<result.height {
                        for x in start..<(start + Int(cell / 2)) { total += Int(alpha(x, y)) }
                    }
                    return total
                }
                let near = wallAlpha(startingAt: 0.5), far = wallAlpha(startingAt: 1.5)
                XCTAssertGreaterThan(far, 0, "Fine frost reaches beyond the dense corner")
                XCTAssertLessThan(far, near / 2, "The front edge fades back to clear ice")

                let gridMargin = (layout.faceRect.width - 18 * layout.cellSize) * scale / 2
                let lastRow = Int(layout.faceRect.height * scale - gridMargin)
                for column in 0..<3 {
                    let x = Int(gridMargin + CGFloat(column) * cell)
                    for y in (lastRow - 1)...(lastRow + 1) {
                        XCTAssertTrue(((x - 1)...(x + 1)).allSatisfy { alpha($0, y) == 0 },
                                      "Frost must leave the lower-left grid crossings clear")
                    }
                }
            }
        }
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

    @MainActor
    func testSurfaceFrostPerimeterFadeKeepsSquareAndRectangularFieldsClear() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let fraction: CGFloat = 0.045
        let rim = BoardSurfaceOverlay(image: image, perimeterFadeFraction: fraction)
        let full = BoardSurfaceOverlay(image: image)

        for size in [CGSize(width: 120, height: 120), CGSize(width: 180, height: 90),
                     CGSize(width: 90, height: 180)] {
            func render(_ surface: BoardSurfaceOverlay, cell: CGFloat) throws
                -> (pixels: [UInt8], width: Int, height: Int) {
                try nativeMaterialPixels(BoardSurfaceOverlayView(surface: surface, cellSize: cell)
                    .frame(width: size.width, height: size.height))
            }
            for cell: CGFloat in [7, 13.99, 14, 20] {
                let result = try render(rim, cell: cell)
                func alpha(_ x: Int, _ y: Int) -> UInt8 {
                    result.pixels[(y * result.width + x) * 4 + 3]
                }
                if cell < 14 {
                    XCTAssertTrue(stride(from: 3, to: result.pixels.count, by: 4)
                        .allSatisfy { result.pixels[$0] == 0 },
                        "A configured perimeter mask draws nothing on a compact board")
                    continue
                }

                // Check the actual native layer with fully opaque source art:
                // every interior pixel must stay clear, not just its center.
                // Leave one device pixel at the fade boundary for antialiasing.
                let inset = Int(ceil(min(size.width, size.height) * fraction * 3)) + 1
                var interiorIsClear = true
                for y in inset..<(result.height - inset) {
                    for x in inset..<(result.width - inset) where alpha(x, y) != 0 {
                        interiorIsClear = false
                    }
                }
                XCTAssertTrue(interiorIsClear, "The narrow rim cannot intrude into the playing field at \(size)")
                for point in [(1, result.height / 2), (result.width - 2, result.height / 2),
                              (result.width / 2, 1), (result.width / 2, result.height - 2)] {
                    XCTAssertGreaterThan(alpha(point.0, point.1), 128,
                                         "Each edge retains visible frost at \(size)")
                }

                let unmasked = try render(full, cell: cell)
                let center = ((unmasked.height / 2) * unmasked.width + unmasked.width / 2) * 4 + 3
                XCTAssertEqual(unmasked.pixels[center], 255,
                               "The default nil mask must retain other overlays' complete artwork")
            }
        }
    }

    @MainActor
    func testBoardTextureVisibilityPreservesSolidSmallBoards() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        func render(opacity: Double, cell: CGFloat) throws -> [UInt8] {
            // Exercise the production modifier used on the combined texture
            // and bevel group, without compiling the interactive board here.
            try nativeMaterialPixels(Color.black.overlay {
                Image(uiImage: image).resizable()
                    .modifier(BoardTextureVisibility(opacity: opacity, cellSize: cell))
            }.frame(width: 48, height: 48)).pixels
        }
        for cell: CGFloat in [7, 13, 13.99, 14, 20] {
            let plain = try render(opacity: 0, cell: cell)
            let quiet = try render(opacity: 0.62, cell: cell)
            let full = try render(opacity: 1, cell: cell)
            if cell < 14 {
                XCTAssertEqual(quiet, plain, "Reduced texture must disappear on solid boards at \(cell) pt")
                XCTAssertEqual(full, plain, "Full-strength texture must disappear on solid boards at \(cell) pt")
            } else {
                XCTAssertNotEqual(quiet, plain, "Detailed boards retain visible material")
                XCTAssertNotEqual(quiet, full, "Texture strength must visibly reduce board noise")
                func colorTotal(_ pixels: [UInt8]) -> Int {
                    var total = 0
                    for index in stride(from: 0, to: pixels.count, by: 4) {
                        total += Int(pixels[index])
                        total += Int(pixels[index + 1])
                        total += Int(pixels[index + 2])
                    }
                    return total
                }
                XCTAssertGreaterThan(colorTotal(quiet), colorTotal(plain))
                XCTAssertLessThan(colorTotal(quiet), colorTotal(full))
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

    /// Changing the landscape must never change Go's flat ink-and-paper
    /// rendering, including on a large board that normally shades stones.
    func testFlowingInkKeepsFlatStonesAndFineStraightGridInEveryVariant() throws {
        for theme: SurroundTheme in [.flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain] {
            XCTAssertNil(theme.colorScheme, "Flowing Ink follows the selected system/app appearance")
            for scheme: ColorScheme in [.light, .dark] {
                let board = theme.board(for: scheme)
                if scheme == .light {
                    let expected: Color = switch theme {
                    case .flowingInkJade: Color(themeHex: 0xDDE7DB)
                    case .flowingInkJadePlain: Color(themeHex: 0xE6BD76)
                    default: .white
                    }
                    XCTAssertEqual(board.boardColor, expected,
                                   "Color uses jade with landscape and wooden yellow without it")
                } else {
                    XCTAssertLessThan(luminance(board.boardColor, style: .dark),
                                      luminance(theme.board(for: .light).boardColor))
                    XCTAssertGreaterThanOrEqual(contrast(.black, board.boardColor, style: .dark), 4.5,
                                               "The dark board still separates its fine grid and labels")
                    XCTAssertGreaterThanOrEqual(contrast(.white, board.boardColor, style: .dark), 3,
                                               "White stones remain distinct on the subdued board")
                }
                XCTAssertEqual(board.surfaceColor(detailed: false), board.boardColor)
                XCTAssertEqual(board.gridStyle, .straight)
                XCTAssertEqual(board.gridColor, .black)
                XCTAssertLessThanOrEqual(board.gridLineScale, 1)
                XCTAssertFalse(board.usesShadedStones)
                XCTAssertFalse(board.castsBoardShadow)
                XCTAssertEqual(board.black.flat, .black)
                XCTAssertEqual(board.white.flat, .white)
                XCTAssertEqual(board.white.outline, .black)
                XCTAssertFalse(board.boardBevel)
                XCTAssertNil(board.boardDepth)
                XCTAssertNil(board.boardTexture)
                XCTAssertNil(board.boardReflection)
                XCTAssertNil(board.surfaceFrost)
                XCTAssertNil(board.stoneImages)
            }
        }
        for scheme: ColorScheme in [.light, .dark] {
            XCTAssertEqual(SurroundTheme.flowingInk.board(for: scheme), SurroundTheme.flowingInkPlain.board(for: scheme))
            XCTAssertNotEqual(SurroundTheme.flowingInkJade.board(for: scheme).boardColor,
                              SurroundTheme.flowingInkJadePlain.board(for: scheme).boardColor)
        }
    }

    func testFlowingInkAdaptiveSurfacesKeepTextAndControlsReadable() throws {
        let players = [
            OGSUser(username: "ordinary", id: 1),
            OGSUser(username: "moderator", id: 2, isModerator: true),
            OGSUser(username: "professional", id: 3, professional: true),
            OGSUser(username: "supporter", id: 4, supporter: true),
        ]
        for theme: SurroundTheme in [.flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain] {
            assertAdaptiveColorsFollowRepeatedTraitChanges(theme)
            for scheme: ColorScheme in [.light, .dark] {
                let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
                try assertNightAnalysisMarksRemainReadable(theme, scheme: scheme)
                for surface in [theme.pageBackground, theme.panel, theme.chatBubble] {
                    XCTAssertGreaterThanOrEqual(contrast(theme.foreground, surface, style: style), 4.5)
                    XCTAssertGreaterThanOrEqual(contrast(theme.detailSecondaryForeground, surface, style: style), 4.5)
                }
                XCTAssertGreaterThanOrEqual(contrast(theme.homeActionForeground, theme.panel, style: style), 4.5,
                                           "The More dots remain readable on their flat panel")
                XCTAssertGreaterThanOrEqual(contrast(.white, try XCTUnwrap(theme.actionTint), style: style), 4.5,
                                           "The main action retains white text in both appearances")
                for color: StoneColor in [.black, .white] {
                    let surface = theme.clockSolidSurface(color)
                    XCTAssertGreaterThanOrEqual(contrast(theme.clockForeground(color, scheme: scheme), surface, style: style), 4.5)
                    XCTAssertGreaterThanOrEqual(contrast(theme.clockAccent(color), surface, style: style), 4.5,
                                               "\(theme) \(scheme): regular accent reads on the \(color) clock")
                    XCTAssertGreaterThanOrEqual(contrast(theme.identityForeground(color), surface, style: style), 4.5)
                    XCTAssertGreaterThanOrEqual(contrast(theme.identitySecondary(color), surface, style: style), 4.5)
                    for player in players {
                        let role = try XCTUnwrap(theme.identityRoleColor(for: player, on: color))
                        XCTAssertGreaterThanOrEqual(contrast(role, surface, style: style), 4.5,
                                                   "\(theme) \(scheme): \(player.username) reads on the \(color) chip")
                    }
                    if scheme == .dark {
                        for (state, accent) in [
                            ("Sudden death", theme.clockSuddenDeathAccent(color, scheme: scheme)),
                            ("Agreement", theme.clockAgreementAccent(color, scheme: scheme)),
                            ("Disconnected", theme.clockDisconnectedAccent(color, scheme: scheme)),
                            ("Undo", theme.clockUndoAccent(color, scheme: scheme)),
                        ] {
                            XCTAssertGreaterThanOrEqual(contrast(accent, surface, style: style), 4.5,
                                                       "\(theme): \(state) reads on the dark \(color) clock")
                        }
                    }
                }
                if scheme == .dark {
                    XCTAssertGreaterThanOrEqual(contrast(.white, theme.clockSuddenDeathBadge(scheme: scheme), style: style), 4.5)
                    XCTAssertGreaterThanOrEqual(contrast(.white, theme.clockUndoBadge(scheme: scheme), style: style), 4.5)
                }
            }
            XCTAssertLessThan(luminance(theme.clockSolidSurface(.white), style: .dark),
                              luminance(theme.clockSolidSurface(.white), style: .light),
                              "Dark Mode softens the flat white controls without adding material")
        }
    }

    @MainActor
    func testLiquidGlassClockTintedShoulderFadesBeforeTheCenter() throws {
        let themes: [SurroundTheme] = [.surroundStudio, .rakedGarden, .nebulaPearl, .sakuraStream]
        XCTAssertEqual(Set(SurroundTheme.allCases.filter(\.usesTintedClockShoulder)), Set(themes))
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let scale: CGFloat = 2
        let padding: CGFloat = 4
        for theme in themes {
            for scheme: ColorScheme in [.light, .dark] {
                let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
                for color: StoneColor in [.black, .white] {
                    for size in [CGSize(width: 88, height: 34), CGSize(width: 190, height: 96),
                                 CGSize(width: 320, height: 28)] {
                        func render(warning: Bool?) throws -> (pixels: [UInt8], width: Int, height: Int) {
                            try nativeMaterialPixelsUsingDirectContext(shape.fill(theme.clockSolidSurface(color))
                                .overlay {
                                    if let warning {
                                        TintedClockShoulder(theme: theme, color: color, isWarning: warning, shape: shape)
                                    }
                                }
                                .frame(width: size.width, height: size.height)
                                .padding(padding)
                                .environment(\.colorScheme, scheme), scale: scale)
                        }
                        let idle = try render(warning: nil)
                        let running = try render(warning: false).pixels
                        let warning = try render(warning: true).pixels
                        let midrow = idle.height / 2
                        func offset(_ x: CGFloat) -> Int {
                            (midrow * idle.width + Int((padding + x) * scale)) * 4
                        }
                        func delta(_ a: [UInt8], _ b: [UInt8], at offset: Int) -> Int {
                            max(abs(Int(a[offset]) - Int(b[offset])),
                                abs(Int(a[offset + 1]) - Int(b[offset + 1])),
                                abs(Int(a[offset + 2]) - Int(b[offset + 2])))
                        }
                        let detail = "\(theme) \(scheme) \(color) \(size)"
                        XCTAssertGreaterThan(delta(running, warning, at: offset(2)), 12,
                                             "Low time has its own shoulder color: \(detail)")
                        for (isWarning, active) in [(false, running), (true, warning)] {
                            let peak = delta(active, idle.pixels, at: offset(2))
                            XCTAssertGreaterThan(peak, 32, "Visible tint at the leading edge: \(detail)")
                            let profile = (3..<Int(size.width / 3)).map {
                                delta(active, idle.pixels, at: offset(CGFloat($0)))
                            }
                            XCTAssertGreaterThan(profile.filter { $0 > 8 && $0 < peak - 5 }.count, 2,
                                                 "Several points of fading tint extend into the face: \(detail)")
                            let protectedX = Int((padding + size.width / 3) * scale)
                            let intrusion = stride(from: 0, to: active.count, by: 4).contains { i in
                                if idle.pixels[i + 3] == 0 { return active[i + 3] > 1 }
                                return i / 4 % idle.width >= protectedX && delta(active, idle.pixels, at: i) > 1
                            }
                            XCTAssertFalse(intrusion, "Keep the tint inside the glass and clear of the center: \(detail)")

                            // Inline clock content can begin eight points from the leading edge.
                            let i = offset(8)
                            let face = Color(.sRGB, red: Double(active[i]) / 255, green: Double(active[i + 1]) / 255,
                                             blue: Double(active[i + 2]) / 255)
                            XCTAssertGreaterThanOrEqual(contrast(theme.clockForeground(color, scheme: scheme), face,
                                                                 style: style), 4.5,
                                                        "Clock text stays legible over the tint: \(detail)")
                            if isWarning {
                                let countdown = theme.clockSuddenDeathAccent(color, scheme: scheme)
                                XCTAssertGreaterThanOrEqual(contrast(countdown, face, style: style), 4.5,
                                                            "Warning countdown stays legible over the tint: \(detail)")
                            }
                        }
                    }
                }
            }
        }
    }

    /// Exercise the exact outline used by the production clock card, rather
    /// than only checking an unused palette token. Header and score cards use
    /// this same view. The UI audit separately exercises the system's read-only
    /// Increase Contrast environment through the supported simulator setting.
    @MainActor
    func testMatteThemeRunningClockOutlineRemainsVisibleAtEverySize() throws {
        for theme: SurroundTheme in [.flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain] {
            for scheme: ColorScheme in [.light, .dark] {
                for color: StoneColor in [.black, .white] {
                    for size in [CGSize(width: 88, height: 32), CGSize(width: 132, height: 48),
                                 CGSize(width: 178, height: 88)] {
                        for scale: CGFloat in [2, 3] {
                          var normalRunningInk: Color?
                          for warning in [false, true] {
                            var widths: [Int] = []
                            for running in [false, true] {
                                let image = try nativeMaterialPixels(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(theme.clockSolidSurface(color))
                                        .overlay { GameDetailMatteClockOutline(color: color, isRunning: running,
                                                                               isWarning: warning, cornerRadius: 12) }
                                        .frame(width: size.width, height: size.height)
                                        .environment(\.surroundTheme, theme)
                                        .environment(\.colorScheme, scheme), scale: scale)
                                func pixel(_ y: Int) -> Color {
                                    let i = (y * image.width + image.width / 2) * 4
                                    return Color(red: Double(image.pixels[i]) / 255,
                                                 green: Double(image.pixels[i + 1]) / 255,
                                                 blue: Double(image.pixels[i + 2]) / 255)
                                }
                                let interior = pixel(image.height / 2)
                                let detail = "\(theme) \(scheme) \(color) \(size) scale=\(scale) warning=\(warning)"
                                if running {
                                    let ringInk = pixel(Int(3 * scale))
                                    XCTAssertGreaterThanOrEqual(contrast(ringInk, interior), 3, detail)
                                    // Even when ring and page match, two points of the clock
                                    // face must separate them before the solid ink begins.
                                    XCTAssertTrue((0..<Int(2 * scale)).allSatisfy { pixel($0) == interior },
                                                  "Face surrounds the running ring: \(detail)")
                                    XCTAssertTrue((Int(2 * scale)..<Int(5 * scale)).allSatisfy { pixel($0) == ringInk },
                                                  "Three continuous points of ink: \(detail)")
                                    XCTAssertEqual(pixel(Int(6 * scale)), interior, detail)
                                    if warning {
                                        XCTAssertNotEqual(ringInk, try XCTUnwrap(normalRunningInk),
                                                          "Low time uses distinct ink on either stone: \(detail)")
                                    } else {
                                        normalRunningInk = ringInk
                                    }
                                } else {
                                    XCTAssertEqual(pixel(Int(2 * scale)), interior, "Idle has no inset ring: \(detail)")
                                }
                                widths.append((0..<Int(7 * scale)).filter {
                                    abs(luminance(pixel($0)) - luminance(interior)) > 0.05
                                }.count)
                            }
                            XCTAssertGreaterThan(widths[1], widths[0], "Running is wider than idle")
                            XCTAssertGreaterThanOrEqual(widths[1], Int(2.5 * scale))
                          }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testFlowingInkExplicitLightOverrideWinsInsideADarkEnvironment() throws {
        struct PaletteProbe: View {
            @Environment(\.surroundTheme) private var theme
            @Environment(\.boardAppearance) private var board
            var body: some View {
                HStack(spacing: 0) {
                    theme.pageBackground
                    theme.panel
                    board.boardColor
                    theme.clockSolidSurface(.black)
                    theme.clockSolidSurface(.white)
                }
                .frame(width: 100, height: 20)
            }
        }
        for theme: SurroundTheme in [.flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain] {
            let light = try nativeMaterialPixels(PaletteProbe().surroundTheme(theme, ownsWindow: false)
                .environment(\.colorScheme, .light)).pixels
            let dark = try nativeMaterialPixels(PaletteProbe().surroundTheme(theme, ownsWindow: false)
                .environment(\.colorScheme, .dark)).pixels
            let overridden = try nativeMaterialPixels(
                ZStack {
                    PaletteProbe().surroundTheme(theme, ownsWindow: false)
                        .environment(\.colorScheme, .light)
                }
                .environment(\.colorScheme, .dark)
            ).pixels
            XCTAssertNotEqual(light, dark, "System Dark Mode must reach both the board and adaptive controls")
            XCTAssertEqual(overridden, light, "An explicit Light appearance must win over a dark parent")
        }
    }

    func testFlowingInkCyclesInOrderAndKeepsOnePickerEntry() {
        let cycle: [SurroundTheme] = [.flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain]
        for (index, theme) in cycle.enumerated() {
            XCTAssertTrue(theme.isFlowingInk)
            XCTAssertEqual(theme.nextFlowingInkTheme, cycle[(index + 1) % cycle.count])
            XCTAssertTrue(theme.hasScene, "Every Flowing mode keeps the app-wide themed surfaces")
            XCTAssertEqual(theme.showsSceneArt, index < 2)
            XCTAssertEqual(theme.flowingInkUsesColor, index == 1 || index == 2)
            XCTAssertEqual(theme.pickerTheme, .flowingInk)
            #if DEBUG
            XCTAssertEqual(SurroundTheme.current(storedID: theme.rawValue), theme,
                           "The persisted theme ID must restore the exact variant")
            #else
            XCTAssertEqual(SurroundTheme.current(storedID: theme.rawValue), .standard)
            #endif
        }
        for theme in SurroundTheme.allCases where !theme.isFlowingInk {
            XCTAssertEqual(theme.nextFlowingInkTheme, .flowingInk)
        }
        #if DEBUG
        XCTAssertEqual(SurroundTheme.pickerThemes.filter(\.isFlowingInk), [.flowingInk])
        #else
        XCTAssertTrue(SurroundTheme.pickerThemes.filter(\.isFlowingInk).isEmpty)
        #endif
    }

    @MainActor
    func testFlowingInkStandaloneStonesIgnoreRequestedShadows() throws {
        func rendered(_ appearance: BoardAppearance, color: StoneColor, size: CGFloat,
                      shadow: CGFloat) throws -> Data {
            let view = Stone(color: color, shadowRadius: shadow)
                .frame(width: size, height: size)
                .padding(12)
                .background(Color(red: 1, green: 0, blue: 1))
                .environment(\.boardAppearance, appearance)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            return try XCTUnwrap(renderer.uiImage?.pngData())
        }
        for theme: SurroundTheme in [.flowingInk, .flowingInkJade] {
            for scheme: ColorScheme in [.light, .dark] {
                for color: StoneColor in [.black, .white] {
                    for size: CGFloat in [7, 13, 20, 40] {
                        XCTAssertEqual(try rendered(theme.board(for: scheme), color: color, size: size, shadow: 4),
                                       try rendered(theme.board(for: scheme), color: color, size: size, shadow: 0),
                                       "\(theme) \(scheme) \(color), \(size) pt stays solid with no shadow")
                    }
                }
            }
        }
        // Prove the comparison detects shading on the ordinary stone path.
        XCTAssertNotEqual(try rendered(.standard, color: .white, size: 40, shadow: 4),
                          try rendered(.standard, color: .white, size: 40, shadow: 0))
    }

    func testFlowingInkArtworkPreservesProportionsAndLandmarksAcrossViewports() {
        let sizes = [CGSize(width: 375, height: 548), CGSize(width: 402, height: 874),
                     CGSize(width: 874, height: 402), CGSize(width: 820, height: 1180),
                     CGSize(width: 1180, height: 820), CGSize(width: 320, height: 320),
                     CGSize(width: 2000, height: 500), CGSize(width: 500, height: 2000)]
        for size in sizes {
            let layout = FlowingInkSceneLayout(size: size)
            let portrait = size.height >= size.width
            let source = portrait ? CGSize(width: 1024, height: 1536) : CGSize(width: 1536, height: 1024)
            XCTAssertEqual(layout.imageSize.width / source.width,
                           layout.imageSize.height / source.height, accuracy: 0.000001,
                           "The painting must be scaled uniformly rather than stretched to the viewport")
            XCTAssertEqual(layout.frame(for: .topLeft).minX, 0, accuracy: 0.001)
            XCTAssertEqual(layout.frame(for: .topLeft).minY, 0, accuracy: 0.001)
            XCTAssertEqual(layout.frame(for: .bottomRight).maxX, size.width, accuracy: 0.001)
            XCTAssertEqual(layout.frame(for: .bottomRight).maxY, size.height, accuracy: 0.001)
            let waterfall = portrait ? CGPoint(x: 0.05, y: 0.65) : CGPoint(x: 0.08, y: 0.70)
            let pine = portrait ? CGPoint(x: 0.85, y: 0.84) : CGPoint(x: 0.85, y: 0.75)
            XCTAssertTrue(layout.opaqueSourceBounds(for: .topLeft).contains(waterfall))
            XCTAssertTrue(layout.opaqueSourceBounds(for: .bottomRight).contains(pine))
        }
        for size in [CGSize.zero, CGSize(width: -1, height: 100),
                     CGSize(width: CGFloat.infinity, height: 100), CGSize(width: 100, height: CGFloat.nan)] {
            let layout = FlowingInkSceneLayout(size: size)
            for corner: FlowingInkSceneLayout.Corner in [.topLeft, .topRight, .bottomLeft, .bottomRight] {
                let frame = layout.frame(for: corner)
                XCTAssertTrue([frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite))
                XCTAssertGreaterThanOrEqual(frame.width, 0)
                XCTAssertGreaterThanOrEqual(frame.height, 0)
            }
        }
    }

    func testFlowingInkLandscapesDecodeAsOpaqueArtwork() throws {
        let bundle = Bundle(for: Self.self)
        for (name, portrait) in [("FlowingInkLandscapePortrait", true),
                                 ("FlowingInkLandscapeLandscape", false)] {
            let image = try XCTUnwrap(UIImage(named: name, in: bundle, compatibleWith: nil), name)
            let source = try XCTUnwrap(image.cgImage, name)
            XCTAssertGreaterThanOrEqual(min(source.width, source.height), 1024)
            XCTAssertEqual(source.height > source.width, portrait)
            let pixels = try rgbaPixels(for: source, side: 128)
            XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 },
                          "The painting includes opaque white paper: \(name)")
            XCTAssertTrue(stride(from: 0, to: pixels.count, by: 4).contains { pixels[$0] < 180 },
                          "The exported artwork must contain visible ink: \(name)")
        }
    }

    func testReefLightKeepsTheGridInTheSeabedAndFlatStonesReadable() throws {
        let theme = SurroundTheme.reefLight
        XCTAssertTrue(theme.isDebugOnly)
        XCTAssertNil(theme.colorScheme)
        for scheme: ColorScheme in [.light, .dark] {
            let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
            let board = theme.board(for: scheme)
            XCTAssertEqual(board.gridStyle, .ragged)
            XCTAssertNil(board.boardDepth)
            XCTAssertFalse(board.boardBevel)
            XCTAssertGreaterThanOrEqual(contrast(board.black.flat, board.white.flat, style: style), 7)
            XCTAssertGreaterThanOrEqual(contrast(theme.detailSecondaryForeground, theme.panel, style: style), 4.5)
            try assertNightControlFallbacksKeepReadableTextAndRoles(theme, scheme: scheme)
        }
    }

    @MainActor
    func testReefLightShellFacesKeepNamesAndClockStatesReadable() throws {
        let theme = SurroundTheme.reefLight
        for name in ["ReefLightAbaloneCorner", "ReefLightAbaloneFoot", "ReefLightPearlCorner", "ReefLightPearlFoot"] {
            XCTAssertNotNil(UIImage(named: name, in: ReefLight.bundle, compatibleWith: nil)?.cgImage, name)
        }
        let cases: [(role: ReefLightShellSurface.Role, size: CGSize)] = [
            (.clock, CGSize(width: 190, height: 96)), (.clock, CGSize(width: 90, height: 34)),
            (.player, CGSize(width: 134, height: 52)), (.player, CGSize(width: 56, height: 44))
        ]
        let players = [OGSUser(username: "supporter", id: 1, supporter: true),
                       OGSUser(username: "moderator", id: 2, isModerator: true)]
        for scheme: ColorScheme in [.light, .dark] {
            let style: UIUserInterfaceStyle = scheme == .light ? .light : .dark
            for color: StoneColor in [.black, .white] {
                XCTAssertGreaterThanOrEqual(contrast(.white, ReefLight.turnBadge(on: color), style: style), 4.5,
                                            "The turn label stays readable on the \(color) player's shell badge")
                for (role, size) in cases {
                    let compact = size.width < 100
                    let image = try nativeMaterialPixels(ReefLightShellSurface(
                        color: color, cornerRadius: 12, role: role, compact: compact)
                        .frame(width: size.width, height: size.height)
                        .environment(\.colorScheme, scheme), scale: 2)
                    let inks = role == .player
                        ? [theme.identityForeground(color), theme.identitySecondary(color)]
                            + players.map { theme.roleColor(for: $0, on: color) }
                        : [theme.clockForeground(color, scheme: scheme), theme.clockAccent(color),
                           theme.clockSuddenDeathAccent(color, scheme: scheme),
                           theme.clockDisconnectedAccent(color, scheme: scheme),
                           theme.clockUndoAccent(color, scheme: scheme), theme.clockAgreementAccent(color, scheme: scheme)]
                    for y in [image.height / 3, image.height / 2, 2 * image.height / 3] {
                        for x in [image.width / 4, image.width / 2, 3 * image.width / 4] {
                            let i = (y * image.width + x) * 4
                            XCTAssertEqual(image.pixels[i + 3], 255, "The face behind the type is opaque")
                            let face = Color(red: Double(image.pixels[i]) / 255,
                                             green: Double(image.pixels[i + 1]) / 255,
                                             blue: Double(image.pixels[i + 2]) / 255)
                            for ink in inks {
                                XCTAssertGreaterThanOrEqual(contrast(ink, face, style: style), 4.5,
                                                            "\(scheme) \(color) \(role) at \(size)")
                            }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testReefLightRunningAndWarningLightFollowTheUpperRightOfTheClock() throws {
        let scale: CGFloat = 2
        for size in [CGSize(width: 190, height: 96), CGSize(width: 88, height: 28)] {
            let width = Int(size.width * scale), height = Int(size.height * scale)
            let corner: CGFloat = size.height < 32 ? 7 : 12
            for scheme: ColorScheme in [.light, .dark] {
                for color: StoneColor in [.black, .white] {
                    let surface = ReefLightShellSurface(color: color, cornerRadius: corner,
                                                        role: .clock, compact: size.height < 32)
                    func render(running: Bool, warning: Bool, plain: Bool) throws -> [UInt8] {
                        try nativeMaterialPixels(surface.overlay {
                            ReefLightClockHighlight(color: color, cornerRadius: corner,
                                                    isRunning: running, isWarning: warning, plain: plain)
                        }
                        .frame(width: size.width, height: size.height)
                        .environment(\.colorScheme, scheme), scale: scale).pixels
                    }
                    let idle = try render(running: false, warning: false, plain: false)
                    XCTAssertTrue(try render(running: false, warning: true, plain: false) == idle,
                                  "An idle clock with little time does not take the active cue")
                    for plain in [false, true] {
                        let running = try render(running: true, warning: false, plain: plain)
                        let warning = try render(running: true, warning: true, plain: plain)
                        let sample = "\(scheme), \(color), \(size), plain=\(plain)"
                        func differs(_ a: [UInt8], _ b: [UInt8], at i: Int) -> Bool {
                            (0..<3).contains { abs(Int(a[i + $0]) - Int(b[i + $0])) > 16 }
                        }
                        let differences = stride(from: 0, to: running.count, by: 4).filter {
                            differs(running, warning, at: $0)
                        }
                        XCTAssertGreaterThan(differences.count, width / 4, "Warning has its own visible ink: \(sample)")
                        for active in [running, warning] {
                            var lit = 0, opposite = 0, content = 0
                            for i in stride(from: 0, to: active.count, by: 4) where differs(active, idle, at: i) {
                                let x = i / 4 % width, y = i / 4 / width
                                if x > width / 2 && y < height / 2 { lit += 1 }
                                if x < width / 2 && y > height / 2 { opposite += 1 }
                                if (width / 5 ..< 4 * width / 5).contains(x)
                                    && (height / 4 ..< 3 * height / 4).contains(y) { content += 1 }
                            }
                            XCTAssertGreaterThan(lit, width / 4, "The active clock catches light at upper right: \(sample)")
                            XCTAssertEqual(content, 0, "The clock digits retain their plate contrast: \(sample)")
                            if plain {
                                XCTAssertGreaterThan(opposite, width / 4, "The solid accessibility outline continues around the clock: \(sample)")
                            } else {
                                XCTAssertGreaterThan(lit, 2 * opposite, "The reflection follows the stone's light: \(sample)")
                            }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testReefLightChipInlayMirrorsAndBecomesAHairlineForAvatarOnly() throws {
        for color: StoneColor in [.black, .white] {
            func render(leading: Bool, hairline: Bool, direction: LayoutDirection) throws
                -> (pixels: [UInt8], width: Int, height: Int) {
                try nativeMaterialPixels(ReefLightShellSurface(
                    color: color, cornerRadius: 12, role: .player, compact: false,
                    shellOnLeading: leading, hairlineOnly: hairline)
                    .frame(width: 146, height: 54).environment(\.layoutDirection, direction), scale: 2)
            }
            for direction: LayoutDirection in [.leftToRight, .rightToLeft] {
                // The shell fragment changes ends with the player. The light on the
                // underlying nacre or abalone still comes from the board's upper right.
                let rim = try render(leading: false, hairline: true, direction: direction)
                func plateBrightness(xPercent: Int, yPercent: Int) -> Double {
                    var sum = 0.0
                    let cx = xPercent * rim.width / 100, cy = yPercent * rim.height / 100
                    for y in (cy - 3)...(cy + 3) {
                        for x in (cx - 3)...(cx + 3) {
                            let i = 4 * (y * rim.width + x)
                            sum += 0.2126 * Double(rim.pixels[i]) + 0.7152 * Double(rim.pixels[i + 1])
                                + 0.0722 * Double(rim.pixels[i + 2])
                        }
                    }
                    return sum / 49
                }
                XCTAssertGreaterThan(plateBrightness(xPercent: 82, yPercent: 20),
                                     plateBrightness(xPercent: 18, yPercent: 80) + 4,
                                     "The physical upper right of the \(color) chip is lit in \(direction)")
                for leading in [true, false] {
                    let chip = try render(leading: leading, hairline: false, direction: direction)
                    let onLeft = leading == (direction == .leftToRight)
                    var changesAtInlay = 0, changesAtAvatar = 0
                    // Skip the outside 2 pt where both ends carry the polished rim.
                    for y in 4..<(chip.height - 4) {
                        for x in 4..<(chip.width - 4) {
                            let i = (y * chip.width + x) * 4
                            guard (i..<(i + 3)).contains(where: {
                                abs(Int(chip.pixels[$0]) - Int(rim.pixels[$0])) > 12
                            }) else { continue }
                            if (x < chip.width / 2) == onLeft { changesAtInlay += 1 }
                            else { changesAtAvatar += 1 }
                        }
                    }
                    XCTAssertGreaterThan(changesAtInlay, 25)
                    XCTAssertGreaterThan(changesAtInlay, 2 * changesAtAvatar,
                                         "The shell should widen at the end away from the avatar: \(color) \(direction)")
                }
            }
        }
    }

    func testReefLightWhiteNacreDarkensAtItsLowerContactEdge() throws {
        let stones = try XCTUnwrap(SurroundTheme.reefLight.board(for: .light).stoneImages)
        let side = 64
        func patchLuma(_ pixels: [UInt8], x: Range<Int>, y: Range<Int>) -> Double {
            var total = 0.0
            var lowestAlpha = UInt8.max
            for row in y {
                for column in x {
                    let offset = (row * side + column) * 4
                    total += 0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1])
                        + 0.0722 * Double(pixels[offset + 2])
                    lowestAlpha = min(lowestAlpha, pixels[offset + 3])
                }
            }
            XCTAssertGreaterThanOrEqual(lowestAlpha, 250, "Measure the shell inside its silhouette")
            return total / Double(x.count * y.count)
        }
        let blackFaces = try stones.black.map { image in
            let pixels = try rgbaPixels(for: XCTUnwrap(image.cgImage), side: side)
            return patchLuma(pixels, x: 23..<41, y: 24..<40)
        }
        let brightestBlack = try XCTUnwrap(blackFaces.max())
        XCTAssertFalse(stones.white.isEmpty)
        for image in stones.white {
            let pixels = try rgbaPixels(for: XCTUnwrap(image.cgImage), side: side)
            let face = patchLuma(pixels, x: 23..<41, y: 24..<40)
            let lowerEdge = patchLuma(pixels, x: 25..<39, y: 57..<60)
            XCTAssertGreaterThan(face - lowerEdge, 10, "White nacre shades into its contact with the sand")
            XCTAssertGreaterThan(face - brightestBlack, 70, "White nacre stays lighter than every dark abalone face")
        }
    }

    @MainActor
    func testReefLightRenderedStoneFacesStayDistinctInDaylightAndMoonlight() throws {
        let linear = (0...255).map { byte -> Double in
            let value = Double(byte) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        for scheme: ColorScheme in [.light, .dark] {
            let board = SurroundTheme.reefLight.board(for: scheme)
            for size: CGFloat in [13, 20] {
                func faceLuminance(_ color: StoneColor) throws -> Double {
                    let image = try nativeMaterialPixels(Stone(color: color, shadowRadius: 1)
                        .frame(width: size, height: size)
                        .background(board.surfaceColor(detailed: size >= 14))
                        .environment(\.boardAppearance, board)
                        .environment(\.colorScheme, scheme)
                        .environment(\.displayScale, 3))
                    let flat = size < 14 ? try nativeMaterialPixels(board.stones(color).flat
                        .frame(width: 1, height: 1), scale: 1).pixels : nil
                    // A broad opaque patch includes the stone's texture without
                    // averaging the contact shadow or sand into either player's face.
                    let xs = image.width / 4 ..< 3 * image.width / 4
                    let ys = image.height / 4 ..< 3 * image.height / 4
                    var luminance = 0.0, matchesFlat = true
                    for y in ys {
                        for x in xs {
                            let i = (y * image.width + x) * 4
                            luminance += 0.2126 * linear[Int(image.pixels[i])]
                                + 0.7152 * linear[Int(image.pixels[i + 1])] + 0.0722 * linear[Int(image.pixels[i + 2])]
                            if let flat { matchesFlat = matchesFlat && image.pixels[i..<i + 4].elementsEqual(flat) }
                        }
                    }
                    XCTAssertTrue(matchesFlat, "Compact \(color) must render its solid \(scheme) pigment")
                    return luminance / Double(xs.count * ys.count)
                }
                let black = try faceLuminance(.black), white = try faceLuminance(.white)
                XCTAssertGreaterThanOrEqual((white + 0.05) / (black + 0.05), size < 14 ? 7 : 5.5,
                                            "Black and White faces at \(size) pt in \(scheme)")
            }
        }
    }

    @MainActor
    func testReefLightNacreHasAnOpenSunlitEdgeAndARoundedShadedShoulder() throws {
        let scale: CGFloat = 3
        for scheme: ColorScheme in [.light, .dark] {
            let board = SurroundTheme.reefLight.board(for: scheme)
            let sand = try XCTUnwrap(board.boardTexture)
            for cell: CGFloat in [20, 32] {
                let diameter = cell - 2 * board.stonePadding(at: cell)
                let image = try nativeMaterialPixels(
                    Image(uiImage: sand.image).resizable().colorMultiply(sand.tint)
                        .frame(width: cell * 19, height: cell * 19)
                        .frame(width: cell * 2, height: cell * 2).clipped()
                        .overlay {
                            Stone(color: .white, shadowRadius: 1)
                                .frame(width: diameter, height: diameter)
                        }
                        .environment(\.boardAppearance, board)
                        .environment(\.colorScheme, scheme)
                        .environment(\.displayScale, scale), scale: scale)
                let radius = diameter * scale / 2
                // Average a sector wide enough to include several shell layers.
                // Fractional radii keep these patches on the same part of the shell at both sizes.
                func patch(heading: Int, radii: [CGFloat]) -> Double {
                    var sum = 0.0
                    let offsets = [-20, -10, 0, 10, 20]
                    for offset in offsets {
                        let angle = CGFloat(heading + offset) * .pi / 180
                        for fraction in radii {
                            let x = Int(CGFloat(image.width) / 2 + cos(angle) * radius * fraction)
                            let y = Int(CGFloat(image.height) / 2 + sin(angle) * radius * fraction)
                            let i = 4 * (y * image.width + x)
                            sum += luminance(Color(.sRGB, red: Double(image.pixels[i]) / 255,
                                                   green: Double(image.pixels[i + 1]) / 255,
                                                   blue: Double(image.pixels[i + 2]) / 255))
                        }
                    }
                    return sum / Double(offsets.count * radii.count)
                }
                let face: [CGFloat] = [0.60, 0.66, 0.72]
                let edge: [CGFloat] = [0.93, 0.95, 0.97]
                let sunlitFace = patch(heading: -45, radii: face)
                let sunlitEdge = patch(heading: -45, radii: edge)
                let shadedFace = patch(heading: 135, radii: face)
                let shoulder = patch(heading: 135, radii: [0.80, 0.84, 0.88])
                let shadedEdge = patch(heading: 135, radii: edge)
                let sandBeyondShadow = patch(heading: 135, radii: [1.26, 1.32])
                let sample = "\(scheme), \(cell) pt"
                XCTAssertGreaterThan((sunlitEdge + 0.05) / (sunlitFace + 0.05), 0.50,
                                     "Sunlight reaches the upper-right edge: \(sample)")
                XCTAssertGreaterThan((shadedFace + 0.05) / (shoulder + 0.05), 1.5,
                                     "The lower-left flank starts rounding well inside the edge: \(sample)")
                XCTAssertGreaterThan((sandBeyondShadow + 0.05) / (shadedEdge + 0.05), scheme == .light ? 3 : 1.45,
                                     "The shaded shell edge separates from the nearby sand: \(sample)")
            }
        }
    }

    func testReefLightUsesTheFullBoardStoneDiameter() throws {
        let cells: [CGFloat] = [7, 9.99, 10, 13.99, 14, 16, 20, 23, 32, 48, 64]
        for scheme: ColorScheme in [.light, .dark] {
            let board = SurroundTheme.reefLight.board(for: scheme)
            let images = try XCTUnwrap(board.stoneImages)
            for cell in cells {
                let padding = board.stonePadding(at: cell)
                let slot = CGRect(x: cell * 3, y: cell * 4, width: cell, height: cell)
                let face = images.displayRect(in: slot.insetBy(dx: padding, dy: padding), cellSize: cell)
                XCTAssertEqual(face.midX, slot.midX, accuracy: 0.000001)
                XCTAssertEqual(face.midY, slot.midY, accuracy: 0.000001)
                XCTAssertEqual(face.width, cell < 10 ? cell : cell - 2, accuracy: 0.000001,
                               "Adjacent stones use the original two-point gap from 10 pt upward")
                XCTAssertEqual(images.displayRect(in: slot, cellSize: cell), slot,
                               "Standalone stone artwork still fills its requested diameter")
            }
        }
    }

    @MainActor
    func testReefLightSandBlendsOutsideThePlayableBoardSlot() throws {
        let size = CGSize(width: 330, height: 330)
        var board = BoardSceneShadowRegion(bounds: CGRect(x: 70, y: 70, width: 190, height: 190),
                                          cellSize: 19)
        func render(_ boards: [BoardSceneShadowRegion]) throws -> [UInt8] {
            try nativeMaterialPixels(ReefLightScene(scheme: .light, boards: boards)
                .frame(width: size.width, height: size.height), scale: 1).pixels
        }
        let reef = try render([])
        let detailed = try render([board])
        func changedPixels(at x: Int) -> Int {
            (110..<220).filter { y in
                let index = (y * Int(size.width) + x) * 4
                return (0..<3).contains { abs(Int(reef[index + $0]) - Int(detailed[index + $0])) > 2 }
            }.count
        }
        XCTAssertGreaterThan(changedPixels(at: 65), 50, "Sand must extend past the clipped board slot")
        XCTAssertEqual(changedPixels(at: 10), 0, "Leave the distant reef visible")
        board.isDetailed = false
        XCTAssertTrue(try render([board]) == reef, "Compact boards supply their own solid surface")
    }

    @MainActor
    func testReefLightDaylightKeepsExposedSandBrightAndWarm() throws {
        let sand = SurroundTheme.reefLight.board(for: .light).boardColor.frame(width: 300, height: 360)
        let unlit = try nativeMaterialPixels(sand, scale: 1)
        let linear = (0...255).map { byte -> Double in
            let value = Double(byte) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        // Sample the deeper lower-left water, where the tint is strongest.
        // Average a patch so the result covers sand between moving ribbons.
        func sample(_ pixels: [UInt8]) -> (light: Double, warmth: Int) {
            var light = 0.0, warmth = 0
            for y in stride(from: 250, to: 310, by: 2) {
                for x in stride(from: 45, to: 105, by: 2) {
                    let i = (y * unlit.width + x) * 4
                    let red = Int(pixels[i]), green = Int(pixels[i + 1]), blue = Int(pixels[i + 2])
                    light += 0.2126 * linear[red] + 0.7152 * linear[green] + 0.0722 * linear[blue]
                    warmth += red - blue
                }
            }
            return (light, warmth)
        }
        let base = sample(unlit.pixels)
        for phase in [0.0, 0.35] {
            let wet = try nativeMaterialPixels(sand.overlay {
                ReefLightWaterSurface(scheme: .light, phase: phase)
            }, scale: 1)
            let water = sample(wet.pixels)
            XCTAssertGreaterThanOrEqual(water.light, base.light * 0.92, "Daylight preserves the sand's luminance")
            XCTAssertGreaterThan(water.warmth, base.warmth / 2, "The sand retains its warm red-to-blue balance")
        }
    }

    @MainActor
    func testReefLightWaterSoftensAcrossTheShellFaceOnly() throws {
        let backdrop = Color(themeHex: 0x0A2A38).frame(width: 220, height: 112)
        let plate = RoundedRectangle(cornerRadius: 12).path(in: CGRect(x: 20, y: 16, width: 100, height: 80))
        let base = try nativeMaterialPixels(backdrop, scale: 1)
        func render(_ shells: [Path]) throws -> [UInt8] {
            try nativeMaterialPixels(backdrop.overlay {
                ReefLightWater(scheme: .light, boards: [], animates: false, shells: shells)
            }, scale: 1).pixels
        }
        let openWater = try render([])
        let shell = try render([plate])
        var openChange = 0, shellChange = 0
        var outsideDifference = 0, outsideChannels = 0, largestDifference = 0
        for y in 28..<84 {
            for x in 30..<110 {
                let i = (y * base.width + x) * 4
                for channel in i..<(i + 3) {
                    openChange += abs(Int(openWater[channel]) - Int(base.pixels[channel]))
                    shellChange += abs(Int(shell[channel]) - Int(base.pixels[channel]))
                }
            }
            let start = (y * base.width + 136) * 4
            let end = (y * base.width + 204) * 4
            for pixel in stride(from: start, to: end, by: 4) {
                for channel in pixel..<(pixel + 3) {
                    let difference = abs(Int(shell[channel]) - Int(openWater[channel]))
                    outsideDifference += difference
                    outsideChannels += 1
                    largestDifference = max(largestDifference, difference)
                }
            }
        }
        // Rasterizing the mask introduces an extra 8-bit compositing pass.
        XCTAssertLessThan(Double(outsideDifference) / Double(outsideChannels), 0.75,
                          "Open water keeps its light outside the clock")
        XCTAssertLessThanOrEqual(largestDifference, 3)
        XCTAssertGreaterThan(shellChange, openChange / 20, "Some of the shared light reaches the clock")
        XCTAssertLessThan(shellChange, openChange / 3, "The matte face diffuses the light behind the time")
    }

    @MainActor
    func testReefLightWaterMovesAcrossTheFieldWithoutObscuringTheSand() throws {
        let size = CGSize(width: 300, height: 360)
        let sand = Color(themeHex: 0xA69B87).frame(width: size.width, height: size.height)
        let background = try nativeMaterialPixels(sand, scale: 1)
        let regions = [
            ("center", 100..<200, 120..<240),
            ("outer edge", 0..<300, 0..<60),
        ]
        let board = BoardSceneShadowRegion(bounds: CGRect(x: 90, y: 100, width: 120, height: 160),
                                           cellSize: 18)
        for scheme: ColorScheme in [.light, .dark] {
            func render(_ phase: Double, board: BoardSceneShadowRegion) throws -> [UInt8] {
                try nativeMaterialPixels(sand.overlay {
                    ReefLightWaterSurface(scheme: scheme, phase: phase, boards: [board])
                }.environment(\.colorScheme, scheme), scale: 1).pixels
            }
            let first = try render(0, board: board), second = try render(0.35, board: board)
            let beforeWrap = try render(0.99999, board: board)
            XCTAssertTrue(zip(beforeWrap, first).allSatisfy { abs(Int($0.0) - Int($0.1)) <= 2 },
                          "The drifting light must meet its starting position without a visible jump")
            for (name, xs, ys) in regions {
                var lit = 0, moved = 0, totalChange = 0
                for y in ys {
                    for x in xs {
                        let offset = (y * background.width + x) * 4
                        var pigmentChange = 0, phaseChange = 0
                        for c in offset..<(offset + 3) {
                            pigmentChange = max(pigmentChange, abs(Int(first[c]) - Int(background.pixels[c])))
                            phaseChange = max(phaseChange, abs(Int(first[c]) - Int(second[c])))
                        }
                        if pigmentChange >= 3 { lit += 1 }
                        if phaseChange >= 2 { moved += 1 }
                        totalChange += pigmentChange
                    }
                }
                let count = xs.count * ys.count
                let sample = "\(scheme) \(name)"
                XCTAssertGreaterThan(lit, count / 100, "Water must register on the sand in the \(sample)")
                XCTAssertGreaterThan(moved, count / 100, "The water pattern must move in the \(sample)")
                XCTAssertLessThan(Double(totalChange) / Double(count), 30,
                                  "The mean color shift must preserve the underlying sand in the \(sample)")
            }
            var compactBoard = board
            compactBoard.isDetailed = false
            compactBoard.cellSize = 13
            let compact = try render(0.35, board: compactBoard)
            let compactStaysSolid = (120..<240).allSatisfy { y in
                let start = (y * background.width + 100) * 4
                let end = (y * background.width + 200) * 4
                return compact[start..<end].elementsEqual(background.pixels[start..<end])
            }
            XCTAssertTrue(compactStaysSolid, "Compact boards keep solid pigment even while surrounding water moves")
        }
    }

    func testWhittledWoodlandUsesCarvedMapleAndReadableWoodenPieces() throws {
        let theme = SurroundTheme.whittledWoodland
        XCTAssertTrue(theme.isDebugOnly)
        XCTAssertNil(theme.colorScheme)
        let day = theme.board(for: .light)
        let night = theme.board(for: .dark)
        XCTAssertEqual(day.boardDepth?.thicknessRatio, night.boardDepth?.thicknessRatio)
        XCTAssertEqual(day.boardDepth?.maximumThickness, night.boardDepth?.maximumThickness)
        XCTAssertNotEqual(day.compactBoardColor, night.compactBoardColor)
        for scheme: ColorScheme in [.light, .dark] {
            let board = theme.board(for: scheme)
            let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
            XCTAssertEqual(board.gridStyle, .incised)
            XCTAssertEqual(try XCTUnwrap(board.boardDepth).edgeStyle, .whittled)
            XCTAssertNotNil(board.boardTexture)
            let images = try XCTUnwrap(board.stoneImages)
            XCTAssertFalse(images.black.isEmpty)
            XCTAssertFalse(images.white.isEmpty)
            XCTAssertGreaterThan(contrast(board.black.flat, board.white.flat, style: style), 7)
            XCTAssertGreaterThan(contrast(theme.detailSecondaryForeground, theme.panel, style: style), 4.5)
            try assertNightControlFallbacksKeepReadableTextAndRoles(theme, scheme: scheme)
        }
    }

    @MainActor
    func testWhittledWoodlandClockAndPlayerHaveDistinctDepthAndReadableWoodFaces() throws {
        let theme = SurroundTheme.whittledWoodland
        let bundle = Bundle(for: Self.self)
        for name in ["WhittledWoodlandWalnutFace", "WhittledWoodlandBirchFace"] {
            XCTAssertNotNil(UIImage(named: name, in: bundle, compatibleWith: nil)?.cgImage, name)
        }
        let players = [OGSUser(username: "ordinary", id: 1),
                       OGSUser(username: "supporter", id: 2, supporter: true),
                       OGSUser(username: "moderator", id: 3, isModerator: true),
                       OGSUser(username: "professional", id: 4, professional: true)]
        for size in [CGSize(width: 184, height: 86), CGSize(width: 92, height: 62)] {
            let rect = CGRect(origin: .zero, size: size)
            let clock = WhittledWoodlandControlShape(cornerRadius: 12, isIdentity: false, faceOnly: true)
            let chip = WhittledWoodlandControlShape(cornerRadius: 12, isIdentity: true, faceOnly: true)
            XCTAssertGreaterThan(chip.path(in: rect).boundingRect.height, clock.path(in: rect).boundingRect.height,
                                 "At a common footprint the clock reserves a deeper bevel than the name plaque")
        }
        let cases: [(size: CGSize, identity: Bool)] = [
            (CGSize(width: 184, height: 86), false), (CGSize(width: 92, height: 116), false),
            (CGSize(width: 158, height: 50), true), (CGSize(width: 82, height: 28), true)
        ]
        for scheme: ColorScheme in [.light, .dark] {
            let style: UIUserInterfaceStyle = scheme == .light ? .light : .dark
            for sample in cases {
                for color: StoneColor in [.black, .white] {
                    let image = try nativeMaterialPixels(
                        WhittledWoodlandControlSurface(color: color, cornerRadius: 12, isIdentity: sample.identity)
                            .frame(width: sample.size.width, height: sample.size.height)
                            .environment(\.colorScheme, scheme), scale: 2)
                    let inks: [(String, Color)] = sample.identity
                        ? [("name", theme.identityForeground(color)), ("rank", theme.identitySecondary(color))]
                            + players.map { ($0.username, theme.roleColor(for: $0, on: color)) }
                        : [("time", theme.clockForeground(color, scheme: scheme)), ("turn", theme.clockAccent(color)),
                           ("sudden death", theme.clockSuddenDeathAccent(color, scheme: scheme)),
                           ("agreement", theme.clockAgreementAccent(color, scheme: scheme)),
                           ("disconnected", theme.clockDisconnectedAccent(color, scheme: scheme)),
                           ("undo", theme.clockUndoAccent(color, scheme: scheme))]
                    let detail = "\(scheme) \(color) \(sample)"
                    XCTAssertLessThan(image.pixels[3], 80, "The actual plaque has a cut corner: \(detail)")
                    var levels = Set<UInt8>()
                    var minimum = 1.0, maximum = 0.0
                    // Sample the real central face on which names and times sit.
                    for y in stride(from: image.height / 4, to: 3 * image.height / 4, by: 4) {
                        for x in stride(from: image.width / 4, to: 3 * image.width / 4, by: 4) {
                            let i = (y * image.width + x) * 4
                            let pixel = Color(.sRGB, red: Double(image.pixels[i]) / 255,
                                              green: Double(image.pixels[i + 1]) / 255,
                                              blue: Double(image.pixels[i + 2]) / 255)
                            let value = luminance(pixel)
                            minimum = min(minimum, value)
                            maximum = max(maximum, value)
                            levels.insert(image.pixels[i])
                        }
                    }
                    XCTAssertGreaterThan(levels.count, 3, "The material has visible wood tones: \(detail)")
                    for (label, ink) in inks {
                        let value = luminance(ink, style: style)
                        let ratio = color == .black ? (value + 0.05) / (maximum + 0.05)
                            : (minimum + 0.05) / (value + 0.05)
                        XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(label) on the actual wood face: \(detail)")
                    }
                }
            }
        }
    }

    @MainActor
    func testWhittledWoodlandRunningInlayFollowsTheCarvedClockFace() throws {
        let theme = SurroundTheme.whittledWoodland
        let sizes: [(size: CGSize, scale: CGFloat, radius: CGFloat, shallow: Bool)] = [
            (CGSize(width: 180, height: 86), 2, 12, false), // Full clock
            (CGSize(width: 116, height: 68), 3, 12, false), // Three compact rows
            (CGSize(width: 96, height: 136), 2, 12, false), // Narrow column
            (CGSize(width: 88, height: 34), 3, 12, false),  // Inline header
            (CGSize(width: 140, height: 28), 3, 8, true)    // Home chip
        ]
        for (size, scale, radius, shallow) in sizes {
            let silhouette = WhittledWoodlandControlShape(cornerRadius: radius, isIdentity: shallow)
            let face = WhittledWoodlandControlShape(cornerRadius: radius, isIdentity: shallow, faceOnly: true)
            func mask(_ shape: WhittledWoodlandControlShape) throws -> [UInt8] {
                try nativeMaterialPixelsUsingDirectContext(shape.fill(.white)
                    .frame(width: size.width, height: size.height), scale: scale).pixels
            }
            let outsideEdge = try mask(silhouette)
            // Allow a half-point for antialiasing along the cut face.
            let textFace = try mask(face.inset(by: 0.5))
            for scheme: ColorScheme in [.light, .dark] {
                for side: StoneColor in [.black, .white] {
                    func render(_ ink: Color?) throws -> (pixels: [UInt8], width: Int, height: Int) {
                        try nativeMaterialPixelsUsingDirectContext(
                            WhittledWoodlandControlSurface(color: side, cornerRadius: radius,
                                                          isIdentity: shallow, runningInk: ink)
                                .frame(width: size.width, height: size.height)
                                .environment(\.colorScheme, scheme), scale: scale)
                    }
                    let idle = try render(nil)
                    let normal = try render(theme.clockAccent(side))
                    let warning = try render(theme.clockSuddenDeathAccent(side, scheme: scheme))
                    let detail = "\(size) \(side) \(scheme)"
                    XCTAssertTrue(normal.pixels != warning.pixels, "Sudden death changes the ink: \(detail)")
                    for active in [normal, warning] {
                        let changed = stride(from: 0, to: idle.pixels.count, by: 4).filter { offset in
                            (0..<4).contains { abs(Int(active.pixels[offset + $0]) - Int(idle.pixels[offset + $0])) > 12 }
                        }
                        XCTAssertGreaterThan(changed.count, Int((size.width + size.height) * scale),
                                             "The running clock has a visible inlay: \(detail)")
                        XCTAssertFalse(changed.contains { textFace[$0 + 3] == 255 },
                                       "Ink must leave the face clear for text: \(detail)")
                        XCTAssertFalse(changed.contains { outsideEdge[$0 + 3] == 0 },
                                       "Ink must stay inside the carved silhouette: \(detail)")
                        let middleX = idle.width / 2, middleY = idle.height / 2
                        let vertical = changed.map { $0 / 4 }.filter { $0 % idle.width == middleX }
                        let horizontal = changed.map { $0 / 4 }.filter { $0 / idle.width == middleY }
                        XCTAssertTrue(vertical.contains { $0 / idle.width < middleY }
                                      && vertical.contains { $0 / idle.width > middleY }
                                      && horizontal.contains { $0 % idle.width < middleX }
                                      && horizontal.contains { $0 % idle.width > middleX },
                                      "The inlay is visible at every side: \(detail)")
                    }
                }
            }
        }
    }

    func testPaperBlossomsKeepsPaperAndFoldedStonesReadableInBothAppearances() throws {
        let theme = SurroundTheme.paperBlossoms
        XCTAssertTrue(theme.isDebugOnly)
        XCTAssertEqual(theme.title, "Paper Blossoms")
        XCTAssertNil(theme.colorScheme, "The surrounding interface follows the chosen appearance")
        for scheme: ColorScheme in [.light, .dark] {
            let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
            let board = theme.board(for: scheme)
            let texture = try XCTUnwrap(board.boardTexture)
            XCTAssertEqual(texture.tint, Color(themeHex: scheme == .dark ? 0xCFBCA0 : 0xDBCAB5))
            XCTAssertEqual(board.surfaceColor(detailed: false),
                           Color(themeHex: scheme == .dark ? 0xD6C0A0 : 0xF3DEC1),
                           "Only the detailed rice-paper texture takes the parchment tint")
            XCTAssertEqual(board.gridStyle, .straight, "The native grid keeps precise playing intersections")
            XCTAssertLessThanOrEqual(board.gridLineScale, 1, "The vermilion grid stays fine")
            XCTAssertNil(board.boardDepth, "Paper does not introduce a thick slab or move the playing surface")
            XCTAssertNil(board.boardReflection, "The paper playing surface stays matte")
            XCTAssertGreaterThanOrEqual(contrast(theme.detailSecondaryForeground, theme.panel, style: style), 4.5,
                                       "The empty Chat composer's placeholder remains readable on paper")
            XCTAssertGreaterThan(contrast(board.black.flat, board.white.flat, style: style), 7)
            XCTAssertGreaterThan(contrast(board.black.flat, board.surfaceColor(detailed: false), style: style), 7)
            XCTAssertGreaterThanOrEqual(contrast(try XCTUnwrap(board.white.outline),
                                               board.surfaceColor(detailed: false), style: style), 3)
            for stone in [board.black, board.white] {
                XCTAssertGreaterThanOrEqual(contrast(stone.label, stone.flat, style: style), 4.5)
                XCTAssertGreaterThanOrEqual(contrast(stone.lastMove, stone.flat, style: style), 3)
                let casing = try XCTUnwrap(stone.detailedMarkerCasing)
                XCTAssertGreaterThanOrEqual(contrast(stone.label, casing, style: style), 4.5,
                                           "Labels retain a readable edge across folded-paper facets")
            }
            try assertNightControlFallbacksKeepReadableTextAndRoles(theme, scheme: scheme)
        }
    }

    @MainActor
    func testPaperBlossomsBackingAppearsOnlyAlongDetailedWhiteStoneEdges() throws {
        for cell: CGFloat in [7, 13.99, 14, 20, 38, 64] {
            let offset = IvoryPaperBacking.offset(forCellSize: cell)
            if cell < 14 {
                XCTAssertEqual(offset, .zero)
            } else {
                XCTAssertGreaterThan(offset.width, 0)
                XCTAssertGreaterThan(offset.height, offset.width)
                XCTAssertLessThan(hypot(offset.width, offset.height), 2,
                                  "Neighboring stone faces have a two-point gap")
            }
        }
        for scheme: ColorScheme in [.light, .dark] {
            for theme in SurroundTheme.allCases {
                XCTAssertEqual(theme.board(for: scheme).hasIvoryPaperBacking, theme == .paperBlossoms)
            }
            let backed = SurroundTheme.paperBlossoms.board(for: scheme)
            var plain = backed
            plain.hasIvoryPaperBacking = false
            for side: StoneColor in [.black, .white] {
                for (diameter, shadow): (CGFloat, CGFloat) in [(13, 1), (14, 1), (20, 0), (20, 1), (38, 1)] {
                    func render(_ board: BoardAppearance) throws -> (pixels: [UInt8], width: Int, height: Int) {
                        try nativeMaterialPixels(Stone(color: side, shadowRadius: shadow)
                            .frame(width: diameter, height: diameter)
                            .padding(4)
                            .background(board.surfaceColor(detailed: false))
                            .environment(\.boardAppearance, board)
                            .environment(\.colorScheme, scheme), scale: 3)
                    }
                    let before = try render(plain), after = try render(backed)
                    let detail = "\(scheme) \(side), \(diameter) pt, shadow \(shadow)"
                    if side == .black || diameter < 14 || shadow == 0 {
                        XCTAssertEqual(after.pixels, before.pixels, detail)
                        continue
                    }
                    let radius = diameter * 3 / 2
                    var edgePixels = 0, maximumFaceChange = 0
                    for y in 0..<after.height {
                        for x in 0..<after.width {
                            let distance = hypot(CGFloat(x) + 0.5 - CGFloat(after.width) / 2,
                                                 CGFloat(y) + 0.5 - CGFloat(after.height) / 2)
                            let index = (y * after.width + x) * 4
                            let redChange = abs(Int(after.pixels[index]) - Int(before.pixels[index]))
                            if distance < radius / 2 {
                                maximumFaceChange = max(maximumFaceChange, redChange)
                            } else if abs(distance - radius) < 6, redChange > 10 {
                                edgePixels += 1
                            }
                        }
                    }
                    XCTAssertGreaterThan(edgePixels, 10, "The exposed paper edge must be visible: \(detail)")
                    XCTAssertLessThanOrEqual(maximumFaceChange, 4,
                                             "Keep the folded face beneath game marks clear: \(detail)")
                }
            }
        }
    }

    func testPaperBlossomsArtworkKeepsNaturalProportionsAcrossGameLayouts() {
        // Phone, short landscape, tablet, square previews, narrow iPad and
        // wide/tall Duo-style slots exercise the actual scene geometry.
        let sizes = [CGSize(width: 375, height: 548), CGSize(width: 375, height: 1000),
                     CGSize(width: 402, height: 874), CGSize(width: 874, height: 402),
                     CGSize(width: 820, height: 1180), CGSize(width: 1180, height: 820),
                     CGSize(width: 320, height: 320), CGSize(width: 2000, height: 500),
                     CGSize(width: 500, height: 2000)]
        for size in sizes {
            let layout = PaperBlossomsSceneLayout(size: size)
            let source = layout.composition.sourceSize
            XCTAssertEqual(layout.imageSize.width / source.width,
                           layout.imageSize.height / source.height, accuracy: 0.000001,
                           "Blossoms, circular lanterns and village buildings must never stretch")
            XCTAssertGreaterThan(layout.scale, 0)
            XCTAssertEqual(layout.frame(for: .topLeft).minX, 0, accuracy: 0.001)
            XCTAssertEqual(layout.frame(for: .topLeft).minY, 0, accuracy: 0.001)
            XCTAssertEqual(layout.frame(for: .bottomRight).maxX, size.width, accuracy: 0.001)
            XCTAssertEqual(layout.frame(for: .bottomRight).maxY, size.height, accuracy: 0.001)
            for corner: PaperBlossomsSceneLayout.Corner in [.topLeft, .topRight, .bottomLeft, .bottomRight] {
                let frame = layout.frame(for: corner)
                XCTAssertGreaterThan(frame.intersection(CGRect(origin: .zero, size: size)).width, 0)
                XCTAssertGreaterThan(frame.intersection(CGRect(origin: .zero, size: size)).height, 0)
            }
        }
        for size in [CGSize.zero, CGSize(width: -1, height: 100),
                     CGSize(width: CGFloat.infinity, height: 100), CGSize(width: 100, height: CGFloat.nan)] {
            let layout = PaperBlossomsSceneLayout(size: size)
            for corner: PaperBlossomsSceneLayout.Corner in [.topLeft, .topRight, .bottomLeft, .bottomRight] {
                let frame = layout.frame(for: corner)
                XCTAssertTrue([frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite))
                XCTAssertGreaterThanOrEqual(frame.width, 0)
                XCTAssertGreaterThanOrEqual(frame.height, 0)
            }
        }
    }

    func testPaperBlossomsArtworkSeparatesOpaquePaperFromTransparentStones() throws {
        let bundle = Bundle(for: Self.self)
        func image(_ name: String) throws -> UIImage {
            try XCTUnwrap(UIImage(named: name, in: bundle, compatibleWith: nil), name)
        }
        for name in ["PaperBlossomsBoard", "PaperBlossomsScenePortrait", "PaperBlossomsSceneLandscape"] {
            let source = try XCTUnwrap(image(name).cgImage, name)
            XCTAssertGreaterThanOrEqual(min(source.width, source.height), 1024)
            let pixels = try rgbaPixels(for: source, side: 128)
            XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 },
                          "The paper must not reveal decoration or grid from a lower layer: \(name)")
            if name.hasSuffix("Portrait") { XCTAssertGreaterThan(source.height, source.width) }
            if name.hasSuffix("Landscape") { XCTAssertGreaterThan(source.width, source.height) }
        }
        let black = try image("PaperBlossomsBlackStone")
        let white = try image("PaperBlossomsWhiteStone")
        XCTAssertNotEqual(black.pngData(), white.pngData(), "The two folded-paper colors need distinct artwork")
        for (name, stone) in [("black", black), ("white", white)] {
            let source = try XCTUnwrap(stone.cgImage)
            XCTAssertEqual(source.width, source.height)
            XCTAssertGreaterThanOrEqual(source.width, 256)
            let pixels = try rgbaPixels(for: source, side: 128)
            XCTAssertEqual(pixels[3], 0, "\(name) stone padding must be transparent")
            XCTAssertGreaterThan(pixels[(64 * 128 + 64) * 4 + 3], 250,
                                 "\(name) stone center must be opaque beneath its marker")
        }
    }

    @MainActor
    func testPaperBlossomsBlackFacetLiftPreservesOtherRendering() throws {
        typealias Raster = (pixels: [UInt8], width: Int, height: Int)
        let scale: CGFloat = 3
        // The unit target compiles Stone.swift, not the complete board view.
        // Native marker-gallery exports cover the board Canvas and game ink.
        func render(_ appearance: BoardAppearance, color: StoneColor, cell: CGFloat) throws -> Raster {
            let content = Stone(color: color, shadowRadius: 1)
                .frame(width: cell, height: cell).padding(8)
                .environment(\.boardAppearance, appearance)
                .environment(\.displayScale, scale)
            return try nativeMaterialPixels(content, scale: scale)
        }
        func brightness(_ pixels: [UInt8], _ offset: Int) -> Double {
            0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1])
                + 0.0722 * Double(pixels[offset + 2])
        }

        for scheme: ColorScheme in [.light, .dark] {
            let lifted = SurroundTheme.paperBlossoms.board(for: scheme)
            var original = lifted
            original.stoneImages?.blackFaceGain = 1
            for color: StoneColor in [.black, .white] {
                for cell: CGFloat in [13, 20] {
                    let before = try render(original, color: color, cell: cell)
                    let after = try render(lifted, color: color, cell: cell)
                    let detail = "\(scheme) \(color), \(cell) pt"
                    XCTAssertEqual(after.width, before.width, detail)
                    XCTAssertEqual(after.height, before.height, detail)
                    if color == .white || cell < 14 {
                        XCTAssertEqual(after.pixels, before.pixels,
                                       "White artwork and compact solids must remain identical: \(detail)")
                        continue
                    }
                    var interiorLift = 0.0, interiorCount = 0, shadowCount = 0
                    var alphaDelta = 0, exteriorDelta = 0
                    for y in 0..<before.height {
                        for x in 0..<before.width {
                            let offset = (y * before.width + x) * 4
                            let dx = (CGFloat(x) + 0.5 - CGFloat(before.width) / 2) / scale
                            let dy = (CGFloat(y) + 0.5 - CGFloat(before.height) / 2) / scale
                            let radiusSquared = dx * dx + dy * dy
                            alphaDelta = max(alphaDelta,
                                abs(Int(after.pixels[offset + 3]) - Int(before.pixels[offset + 3])))
                            // The normalized paper asset's interior alpha is
                            // 252–254; do not discard its near-opaque face.
                            if radiusSquared < cell * cell / 16, before.pixels[offset + 3] > 250 {
                                interiorLift += brightness(after.pixels, offset) - brightness(before.pixels, offset)
                                interiorCount += 1
                            }
                            if radiusSquared > (cell / 2 + 1) * (cell / 2 + 1) {
                                if before.pixels[offset + 3] > 0 { shadowCount += 1 }
                                for channel in 0..<4 {
                                    exteriorDelta = max(exteriorDelta,
                                        abs(Int(after.pixels[offset + channel]) - Int(before.pixels[offset + channel])))
                                }
                            }
                        }
                    }
                    XCTAssertGreaterThan(interiorCount, 20, detail)
                    XCTAssertGreaterThan(interiorLift / Double(max(1, interiorCount)), 2,
                                         "Native black folds need a visible lift: \(detail)")
                    XCTAssertLessThanOrEqual(alphaDelta, 1, "Preserve silhouette alpha: \(detail)")
                    XCTAssertGreaterThan(shadowCount, 0, "Sample the actual native shadow: \(detail)")
                    XCTAssertLessThanOrEqual(exteriorDelta, 1,
                                             "Neither shadows nor transparent padding may brighten: \(detail)")
                }
            }
        }
    }

    @MainActor
    func testPaperBlossomsGameControlEdgesReadAgainstTheGarden() throws {
        let theme = SurroundTheme.paperBlossoms
        for scheme: ColorScheme in [.light, .dark] {
            let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
            // Garden colors beside Next in iPhone portrait and above the black
            // identity in iPad landscape, where the red paper is brighter.
            let actionScene = Color(themeHex: scheme == .dark ? 0x4B0907 : 0xB30D09)
            let chipScene = Color(themeHex: scheme == .dark ? 0x500A07 : 0xBE0F07)
            let actionFace = try XCTUnwrap(theme.actionTint)
            let chipFace = theme.clockSolidSurface(.black)
            for scale: CGFloat in [2, 3] {
                func checkEdge<V: View>(_ view: V, width: CGFloat, scene: Color) throws {
                    let image = try nativeMaterialPixels(view.frame(width: width, height: 44)
                        .background(scene).environment(\.colorScheme, scheme), scale: scale)
                    func pixel(row: Int) -> Color {
                        let i = (row * image.width + image.width / 2) * 4
                        return Color(.sRGB, red: Double(image.pixels[i]) / 255,
                                     green: Double(image.pixels[i + 1]) / 255,
                                     blue: Double(image.pixels[i + 2]) / 255)
                    }
                    let face = pixel(row: image.height / 2)
                    // Inspect the straight center of the edge; the same pixel
                    // must separate from both the face and the neighboring garden.
                    let strength = (0..<Int(2 * scale)).map { row in
                        min(contrast(pixel(row: row), face, style: style),
                            contrast(pixel(row: row), scene, style: style))
                    }.max() ?? 0
                    XCTAssertGreaterThanOrEqual(strength, 3, "\(scheme), \(width) pt, \(scale)×")
                }
                try checkEdge(Capsule().fill(actionFace).overlay {
                    PaperBlossomsActionOutline(prominent: true, interactive: true, disabled: false)
                }, width: 132, scene: actionScene)
                try checkEdge(PaperBlossomsControlShape(cornerRadius: 9, compact: true).fill(chipFace)
                    .overlay { PaperBlossomsIdentityOutline(color: .black, cornerRadius: 9, compact: true) },
                    width: 156, scene: chipScene)
            }
        }
    }

    @MainActor
    func testPaperBlossomsControlEdgesPreserveSecondaryStatesAndWhiteIdentity() throws {
        for (prominent, interactive, disabled) in [(false, true, false), (true, true, true), (true, false, false)] {
            let outline = try nativeMaterialPixelsUsingDirectContext(PaperBlossomsActionOutline(
                prominent: prominent, interactive: interactive, disabled: disabled
            ).frame(width: 132, height: 44))
            XCTAssertTrue(stride(from: 3, to: outline.pixels.count, by: 4).allSatisfy { outline.pixels[$0] == 0 },
                          "Only the enabled primary action gains an ivory edge")
        }
        for scheme: ColorScheme in [.light, .dark] {
            let white = try nativeMaterialPixels(PaperBlossomsIdentityOutline(
                color: .white, cornerRadius: 9, compact: true
            ).frame(width: 126, height: 44).environment(\.colorScheme, scheme))
            let existing = try nativeMaterialPixels(PaperBlossomsControlShape(
                cornerRadius: 9, compact: true, faceOnly: true
            ).strokeBorder(SurroundTheme.paperBlossoms.identityChipBorder(.white), lineWidth: 1)
                .frame(width: 126, height: 44).environment(\.colorScheme, scheme))
            XCTAssertEqual(white.pixels, existing.pixels, "The white identity keeps its fine folded-paper contour")
        }
    }

    @MainActor
    func testPaperBlossomsClockPrintCoversTheFaceAndKeepsTimeReadable() throws {
        let theme = SurroundTheme.paperBlossoms
        func difference(_ a: [UInt8], _ b: [UInt8], at i: Int) -> Int {
            max(abs(Int(a[i]) - Int(b[i])), abs(Int(a[i + 1]) - Int(b[i + 1])),
                abs(Int(a[i + 2]) - Int(b[i + 2])))
        }

        for scheme: ColorScheme in [.light, .dark] {
            let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
            for color: StoneColor in [.black, .white] {
                func check<Face: InsettableShape, Paper: ShapeStyle>(_ face: Face, fill: Paper, size: CGSize,
                                                                    placement: PaperBlossomsClockPrint<Face>.Placement) throws {
                    func render(warning: Bool?) throws -> [UInt8] {
                        try nativeMaterialPixelsUsingDirectContext(face.fill(fill).overlay {
                            if let warning {
                                PaperBlossomsClockPrint(shape: face, color: color, isWarning: warning,
                                                       placement: placement)
                            }
                        }.frame(width: size.width, height: size.height).padding(2)
                         .environment(\.colorScheme, scheme), scale: 2).pixels
                    }
                    let idle = try render(warning: nil)
                    let running = try render(warning: false)
                    let warning = try render(warning: true)
                    let detail = "\(color), \(scheme), \(size), \(placement)"
                    for isWarning in [false, true] {
                        let active = isWarning ? warning : running
                        var facePixels = 0, printedPixels = 0, escapedPixels = 0
                        var largestDifference = 0, inkSample = 0
                        for i in stride(from: 0, to: idle.count, by: 4) {
                            if idle[i + 3] == 0 && active[i + 3] > 3 { escapedPixels += 1 }
                            guard idle[i + 3] == 255 else { continue }
                            facePixels += 1
                            let change = difference(active, idle, at: i)
                            if change > 24 { printedPixels += 1 }
                            if change > largestDifference {
                                largestDifference = change
                                inkSample = i
                            }
                        }
                        XCTAssertEqual(escapedPixels, 0, "Keep the fold and the exterior clear: \(detail)")
                        let coverage = Double(printedPixels) / Double(facePixels)
                        XCTAssertGreaterThan(coverage, 0.12, "The print must survive the smallest layout: \(detail)")
                        XCTAssertLessThan(coverage, 0.65, "Leave the original paper visible between petals: \(detail)")
                        XCTAssertGreaterThan(difference(running, warning, at: inkSample), 12,
                                             "Low time uses a distinct print: \(detail)")
                        let ink = Color(.sRGB, red: Double(active[inkSample]) / 255,
                                        green: Double(active[inkSample + 1]) / 255,
                                        blue: Double(active[inkSample + 2]) / 255)
                        let timer = isWarning ? theme.clockSuddenDeathAccent(color, scheme: scheme)
                                              : theme.clockForeground(color, scheme: scheme)
                        XCTAssertGreaterThanOrEqual(contrast(timer, ink, style: style), 4.5,
                                                    "The countdown stays readable over a petal: \(detail)")
                        if case .strip(carriesSecondaryText: true) = placement {
                            XCTAssertGreaterThanOrEqual(contrast(theme.identitySecondary(color), ink, style: style), 4.5,
                                                        "Secondary text stays readable over a petal: \(detail)")
                        }
                    }
                }

                let paper = theme.clockSolidSurface(color)
                for (size, strip) in [(CGSize(width: 190, height: 96), false),
                                      (CGSize(width: 150, height: 60), false),
                                      (CGSize(width: 88, height: 34), true)] {
                    let face = PaperBlossomsControlShape(cornerRadius: 12, compact: strip, faceOnly: true)
                    try check(face, fill: paper, size: size, placement: strip ? .strip(carriesSecondaryText: true)
                                                                              : .card(countdownTrailing: color == .white))
                }
                let unfolded = PaperBlossomsControlShape(cornerRadius: 12, compact: true, faceOnly: true, folded: false)
                try check(unfolded, fill: paper, size: CGSize(width: 88, height: 34),
                          placement: .strip(carriesSecondaryText: true))
                let home = RoundedRectangle(cornerRadius: 8, style: .continuous)
                let gradient = LinearGradient(colors: theme.identityChipColors(color), startPoint: .top, endPoint: .bottom)
                for carriesSecondaryText in [false, true] {
                    try check(home, fill: gradient, size: CGSize(width: 140, height: 28),
                              placement: .strip(carriesSecondaryText: carriesSecondaryText))
                }
            }
        }
    }

    @MainActor
    func testPaperBlossomsTurnedCornerKeepsTheTextFaceClear() throws {
        let theme = SurroundTheme.paperBlossoms
        let scale: CGFloat = 2
        let asset = try XCTUnwrap(UIImage(named: "PaperBlossomsTurnedCorner",
                                         in: Bundle(for: Self.self), compatibleWith: nil))
        XCTAssertNotNil(asset.cgImage, "The actual vermilion reverse must ship in the theme catalog")
        let linear = (0...255).map { byte -> Double in
            let value = Double(byte) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        func pixelLuminance(_ pixels: [UInt8], _ offset: Int) -> Double {
            let red = linear[Int(pixels[offset])]
            let green = linear[Int(pixels[offset + 1])]
            let blue = linear[Int(pixels[offset + 2])]
            return 0.2126 * red + 0.7152 * green + 0.0722 * blue
        }
        let players = [OGSUser(username: "ordinary", id: 1),
                       OGSUser(username: "moderator", id: 2, isModerator: true),
                       OGSUser(username: "professional", id: 3, professional: true),
                       OGSUser(username: "supporter", id: 4, supporter: true)]
        let sizes: [(CGSize, CGFloat, Bool)] = [
            (CGSize(width: 88, height: 34), 12, true),
            (CGSize(width: 178, height: 88), 12, false),
            (CGSize(width: 126, height: 140), 9, false)
        ]
        for scheme: ColorScheme in [.light, .dark] {
            let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
            for color: StoneColor in [.black, .white] {
                let inks = [theme.clockForeground(color, scheme: scheme), theme.identitySecondary(color),
                            theme.clockAccent(color), theme.clockSuddenDeathAccent(color, scheme: scheme),
                            theme.clockAgreementAccent(color, scheme: scheme),
                            theme.clockDisconnectedAccent(color, scheme: scheme),
                            theme.clockUndoAccent(color, scheme: scheme)]
                    + players.map { theme.roleColor(for: $0, on: color) }
                for (size, radius, compact) in sizes {
                    let fold: CGFloat = compact ? 12 : 20
                    let clearance: CGFloat = compact ? 14 : 22
                    let flat = try nativeMaterialPixels(theme.clockSolidSurface(color)
                        .frame(width: size.width, height: size.height)
                        .environment(\.colorScheme, scheme), scale: scale)
                    let interior = try nativeMaterialPixels(PaperBlossomsControlShape(
                        cornerRadius: radius, compact: compact).inset(by: 1).fill(.white)
                        .frame(width: size.width, height: size.height), scale: scale)
                    // Native stroke coverage avoids counting pixels that only
                    // partly intersect an antialiased curved crease.
                    let protectedPerimeter = try nativeMaterialPixels(PaperBlossomsControlShape(
                        cornerRadius: radius, compact: compact, faceOnly: true)
                        .strokeBorder(.white, lineWidth: 4)
                        .frame(width: size.width, height: size.height), scale: scale)
                    // Accessibility flags are read-only SwiftUI environment
                    // values; fallback selection is reviewed in production.
                    let rendered = try nativeMaterialPixels(PaperBlossomsControlSurface(
                        color: color, cornerRadius: radius, compact: compact)
                        .frame(width: size.width, height: size.height)
                        .environment(\.colorScheme, scheme), scale: scale)
                    let detail = "\(scheme) \(color) \(size)"
                    XCTAssertEqual(rendered.width, flat.width, detail)
                    XCTAssertEqual(rendered.height, flat.height, detail)
                    var minimum = Double.infinity, maximum = 0.0
                    var opaqueFailures = 0, textSamples = 0, flatFaceDelta = 0
                    var tipSamples = 0, tipAlpha = 0, redPixels = 0, misplacedRed = 0
                    var perimeterSamples = 0, redUnderPerimeter = 0
                    for y in 0..<rendered.height {
                        for x in 0..<rendered.width {
                            let offset = (y * rendered.width + x) * 4
                            let point = CGPoint(x: (CGFloat(x) + 0.5) / scale,
                                                y: (CGFloat(y) + 0.5) / scale)
                            let alpha = Int(rendered.pixels[offset + 3])
                            if interior.pixels[offset + 3] == 255 && alpha != 255 {
                                opaqueFailures += 1
                            }
                            // The selected shape removes the original tip;
                            // decoration alone on a rectangular card cannot pass.
                            if point.x > size.width - fold / 4 && point.y > size.height - fold / 4 {
                                tipSamples += 1
                                tipAlpha = max(tipAlpha, alpha)
                            }
                            let red = Int(rendered.pixels[offset])
                            let green = Int(rendered.pixels[offset + 1])
                            let blue = Int(rendered.pixels[offset + 2])
                            let isVermilion = alpha == 255 && red > green + 20 && red > blue + 20
                            if isVermilion {
                                redPixels += 1
                                if point.x < size.width - fold - 1 || point.y < size.height - fold - 1 {
                                    misplacedRed += 1
                                }
                            }
                            // Text is inset from the corner. Keep the broad
                            // face unchanged, excluding only its local shadow.
                            if interior.pixels[offset + 3] == 255,
                               point.x < size.width - clearance - 2 {
                                textSamples += 1
                                for channel in 0..<4 {
                                    flatFaceDelta = max(flatFaceDelta,
                                        abs(Int(rendered.pixels[offset + channel]) - Int(flat.pixels[offset + channel])))
                                }
                                let value = pixelLuminance(rendered.pixels, offset)
                                minimum = min(minimum, value)
                                maximum = max(maximum, value)
                            }
                            if protectedPerimeter.pixels[offset + 3] == 255 {
                                perimeterSamples += 1
                                if isVermilion { redUnderPerimeter += 1 }
                            }
                        }
                    }
                    XCTAssertEqual(opaqueFailures, 0, "Paper face and reverse must be opaque: \(detail)")
                    XCTAssertGreaterThan(tipSamples, 3, detail)
                    XCTAssertEqual(tipAlpha, 0, "The dog-ear must cut the actual silhouette: \(detail)")
                    XCTAssertGreaterThan(redPixels, 8, "Show a visible vermilion reverse: \(detail)")
                    XCTAssertEqual(misplacedRed, 0, "Keep the ornament out of the text face: \(detail)")
                    XCTAssertGreaterThan(textSamples, 500, detail)
                    XCTAssertLessThanOrEqual(flatFaceDelta, 1, "No broad facet shading may return: \(detail)")
                    XCTAssertGreaterThan(perimeterSamples, 100, detail)
                    XCTAssertEqual(redUnderPerimeter, 0, "The folded reverse stays behind the crease: \(detail)")
                    for ink in inks {
                        let value = luminance(ink, style: style)
                        for surface in [minimum, maximum] {
                            XCTAssertGreaterThanOrEqual((max(value, surface) + 0.05)
                                / (min(value, surface) + 0.05), 4.5,
                                "Every role and state must read on the reserved text face: \(detail)")
                        }
                    }
                }
            }
        }
    }

    func testSakuraStreamControlsAndAnalysisStayReadableAcrossAppearances() throws {
        let theme = SurroundTheme.sakuraStream
        for scheme: ColorScheme in [.light, .dark] {
            let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
            try assertNightControlFallbacksKeepReadableTextAndRoles(theme, scheme: scheme)
            try assertNightAnalysisMarksRemainReadable(theme, scheme: scheme)
            for surface in [theme.pageBackground, theme.panel, theme.chatBubble] {
                XCTAssertGreaterThanOrEqual(contrast(theme.detailSecondaryForeground, surface, style: style), 4.5)
            }
            for surface in [theme.panel, theme.chatBubble] {
                XCTAssertGreaterThanOrEqual(contrast(theme.chatCoordinateForeground, surface, style: style), 4.5)
            }
            for surface in [theme.pageBackground, theme.panel] {
                XCTAssertGreaterThanOrEqual(contrast(theme.homeActionForeground, surface, style: style), 4.5)
            }
        }
        assertAdaptiveColorsFollowRepeatedTraitChanges(theme)
    }

    @MainActor
    func testSakuraStreamSolidGlassFallbackKeepsTextReadableAcrossSizes() throws {
        let theme = SurroundTheme.sakuraStream
        let scale = 3
        let linear = (0...255).map { byte -> Double in
            let value = Double(byte) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let players = [OGSUser(username: "ordinary", id: 1),
                       OGSUser(username: "moderator", id: 2, isModerator: true),
                       OGSUser(username: "professional", id: 3, professional: true),
                       OGSUser(username: "supporter", id: 4, supporter: true),
                       OGSUser(username: "bot", id: 5, isBot: true)]
        let cases: [(name: String, size: CGSize,
                     inset: CGSize, radius: CGFloat, compact: Bool, player: Bool)] = [
            ("full clock", CGSize(width: 190, height: 96), CGSize(width: 12, height: 4), 12, false, false),
            ("narrow clock", CGSize(width: 104, height: 144), CGSize(width: 10, height: 4), 12, true, false),
            ("compact clock", CGSize(width: 160, height: 52), CGSize(width: 8, height: 4), 12, true, false),
            ("inline clock", CGSize(width: 140, height: 34), CGSize(width: 8, height: 4), 12, true, false),
            ("wide inline clock", CGSize(width: 320, height: 34), CGSize(width: 8, height: 4), 12, true, false),
            ("row player", CGSize(width: 156, height: 52), CGSize(width: 4, height: 4), 10, false, true),
            ("column player", CGSize(width: 126, height: 84), CGSize(width: 5, height: 5), 9, true, true),
            ("vertical player", CGSize(width: 156, height: 144), CGSize(width: 8, height: 8), 12, false, true),
            ("header player", CGSize(width: 220, height: 44), CGSize(width: 4, height: 8), 10, true, true)
        ]
        let modes: [(name: String, reduced: Bool, contrast: ColorSchemeContrast)] = [
            ("reduced transparency", true, .standard),
            ("increased contrast", false, .increased)
        ]
        for scheme: ColorScheme in [.light, .dark] {
            let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
            for color: StoneColor in [.black, .white] {
                let identityInks: [(String, Color)] = [
                    ("identity", theme.identityForeground(color)),
                    ("secondary", theme.identitySecondary(color))
                ] + players.map { ($0.username, theme.roleColor(for: $0, on: color)) }
                let clockInks: [(String, Color)] = [
                    ("clock", theme.clockForeground(color, scheme: scheme)),
                    ("accent", theme.clockAccent(color)),
                    ("sudden death", theme.clockSuddenDeathAccent(color, scheme: scheme)),
                    ("agreement", theme.clockAgreementAccent(color, scheme: scheme)),
                    ("disconnected", theme.clockDisconnectedAccent(color, scheme: scheme)),
                    ("undo", theme.clockUndoAccent(color, scheme: scheme))
                ]
                for sample in cases {
                    for mode in modes {
                        let rendered = try nativeMaterialPixels(SakuraStreamSolidControlSurface(
                            color: color, cornerRadius: sample.radius, scheme: scheme, contrast: mode.contrast)
                            .overlay {
                                SakuraStreamGlassEtchDrawing(color: color, cornerRadius: sample.radius,
                                    role: sample.player ? .player : .clock, compact: sample.compact,
                                    scheme: scheme, reduceTransparency: mode.reduced, contrast: mode.contrast)
                            }
                            .frame(width: sample.size.width, height: sample.size.height)
                            .environment(\.colorScheme, scheme))
                        let message = "\(sample.name), \(scheme), \(color), \(mode.name)"
                        XCTAssertEqual(rendered.width, Int(sample.size.width) * scale, message)
                        XCTAssertEqual(rendered.height, Int(sample.size.height) * scale, message)
                        // Use actual clock/header/player text reserves. Solid
                        // accessibility surfaces must remain undecorated and
                        // readable through the final 4 pt metadata padding.
                        let textRect = CGRect(origin: .zero, size: sample.size)
                            .insetBy(dx: sample.inset.width, dy: sample.inset.height)
                        // Padding reserves a rounded interior, not the corner
                        // cutouts or their outline. Retain the full straight
                        // bottom reserve, where metadata can reach within 4 pt.
                        let edgeInset = min(sample.inset.width, sample.inset.height)
                        let roundedReserve = RoundedRectangle(cornerRadius: max(0, sample.radius - edgeInset),
                                                              style: .circular)
                            .path(in: CGRect(origin: .zero, size: sample.size)
                                .insetBy(dx: edgeInset, dy: edgeInset))
                        var minimum = Double.infinity, maximum = 0.0
                        var darkestPoint = CGPoint.zero, brightestPoint = CGPoint.zero
                        var minimumAlpha: UInt8 = 255
                        for y in Int(textRect.minY) * scale..<Int(textRect.maxY) * scale {
                            for x in Int(textRect.minX) * scale..<Int(textRect.maxX) * scale {
                                let point = CGPoint(x: (CGFloat(x) + 0.5) / CGFloat(scale),
                                                    y: (CGFloat(y) + 0.5) / CGFloat(scale))
                                guard roundedReserve.contains(point) else { continue }
                                let offset = (y * rendered.width + x) * 4
                                minimumAlpha = min(minimumAlpha, rendered.pixels[offset + 3])
                                let red = linear[Int(rendered.pixels[offset])]
                                let green = linear[Int(rendered.pixels[offset + 1])]
                                let blue = linear[Int(rendered.pixels[offset + 2])]
                                let value = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                                if value < minimum { minimum = value; darkestPoint = point }
                                if value > maximum { maximum = value; brightestPoint = point }
                            }
                        }
                        XCTAssertEqual(minimumAlpha, 255, "The text backing stays opaque: \(message)")
                        for (name, ink) in sample.player ? identityInks : clockInks {
                            let value = luminance(ink, style: style)
                            let nearest = min(maximum, max(minimum, value))
                            XCTAssertGreaterThanOrEqual((max(value, nearest) + 0.05)
                                / (min(value, nearest) + 0.05), 4.5,
                                "\(name): \(message); dark \(minimum) at \(darkestPoint), light \(maximum) at \(brightestPoint)")
                        }
                        XCTAssertLessThan(maximum - minimum, 0.001,
                                          "Accessibility text backing stays solid: \(message)")
                    }
                }
            }
        }
    }

    @MainActor
    func testSakuraStreamGlassEtchingStaysOutsideContentAndSuppressesCompactControls() throws {
        let samples: [(name: String, size: CGSize, radius: CGFloat,
                       role: SakuraStreamGlassEtching.Role, compact: Bool)] = [
            ("full clock", CGSize(width: 190, height: 96), 12, .clock, false),
            ("row player", CGSize(width: 156, height: 52), 10, .player, false),
            ("vertical player", CGSize(width: 156, height: 144), 12, .player, false),
            ("compact clock", CGSize(width: 160, height: 52), 12, .clock, true),
            ("inline clock", CGSize(width: 140, height: 34), 12, .clock, true),
            ("narrow clock", CGSize(width: 104, height: 144), 12, .clock, true),
            ("column player", CGSize(width: 126, height: 84), 9, .player, true),
            ("header player", CGSize(width: 220, height: 44), 10, .player, true),
            // Size gates protect callers even if their compact flag is absent.
            ("small clock", CGSize(width: 104, height: 96), 12, .clock, false),
            ("short player", CGSize(width: 156, height: 44), 10, .player, false)
        ]
        for scheme: ColorScheme in [.light, .dark] {
            for color: StoneColor in [.black, .white] {
                for sample in samples {
                    func render(reduced: Bool = false, increased: Bool = false) throws
                        -> (pixels: [UInt8], width: Int, height: Int) {
                        try nativeMaterialPixels(SakuraStreamGlassEtchDrawing(color: color,
                            cornerRadius: sample.radius, role: sample.role, compact: sample.compact,
                            scheme: scheme, reduceTransparency: reduced, contrast: increased ? .increased : .standard)
                            .frame(width: sample.size.width, height: sample.size.height)
                            .environment(\.colorScheme, scheme))
                    }
                    let image = try render()
                    let message = "\(sample.name), \(scheme), \(color)"
                    let shouldDraw = !sample.compact
                        && sample.size.width >= (sample.role == .clock ? 140 : 120)
                        && sample.size.height >= (sample.role == .clock ? 80 : 48)
                    var visible = 0
                    let reserve = CGRect(origin: .zero, size: sample.size).insetBy(dx: 4, dy: 4)
                    for y in 0..<image.height {
                        for x in 0..<image.width {
                            let alpha = image.pixels[(y * image.width + x) * 4 + 3]
                            guard alpha != 0 else { continue }
                            visible += 1
                            let point = CGPoint(x: (CGFloat(x) + 0.5) / 3, y: (CGFloat(y) + 0.5) / 3)
                            XCTAssertFalse(reserve.contains(point), "Etching cannot enter text/avatar reserve: \(message)")
                            XCTAssertGreaterThan(x, 0, "No exterior decoration: \(message)")
                            XCTAssertGreaterThan(y, 0, "No exterior decoration: \(message)")
                            XCTAssertLessThan(x, image.width - 1, message)
                            XCTAssertLessThan(y, image.height - 1, message)
                            XCTAssertLessThanOrEqual(alpha, 85, "Etching remains a quiet translucent line: \(message)")
                        }
                    }
                    if shouldDraw {
                        XCTAssertGreaterThan(visible, 20, "Both side colors retain an actual etch: \(message)")
                        XCTAssertLessThan(visible, image.width * image.height / 20,
                                          "Sparse corners, not a continuous ornamental border: \(message)")
                    } else {
                        XCTAssertEqual(visible, 0, "Compact and header controls stay undecorated: \(message)")
                    }
                    for solid in [try render(reduced: true), try render(increased: true)] {
                        XCTAssertTrue(stride(from: 3, to: solid.pixels.count, by: 4)
                            .allSatisfy { solid.pixels[$0] == 0 },
                            "Accessibility fallback has no etched decoration: \(message)")
                    }
                }
            }
        }
    }

    @MainActor
    func testSakuraStreamGlassBlossomUsesOnlyTheReservedHeaderPocket() throws {
        for scheme: ColorScheme in [.light, .dark] {
            for mirrored in [false, true] {
                for color: StoneColor in [.black, .white] {
                    func render(spare: Bool, compact: Bool = false, reduced: Bool = false,
                                increased: Bool = false) throws -> (pixels: [UInt8], width: Int, height: Int) {
                        try nativeMaterialPixels(SakuraStreamGlassEtchDrawing(color: color, cornerRadius: 12,
                            role: .clock, compact: compact, spareClockCorner: spare, mirrored: mirrored,
                            scheme: scheme, reduceTransparency: reduced, contrast: increased ? .increased : .standard)
                            .frame(width: 190, height: 96).environment(\.colorScheme, scheme))
                    }
                    let edge = try render(spare: false), blossom = try render(spare: true)
                    var changed = 0
                    for y in 0..<edge.height {
                        for x in 0..<edge.width {
                            let offset = (y * edge.width + x) * 4
                            guard (0..<4).contains(where: { edge.pixels[offset + $0] != blossom.pixels[offset + $0] }) else { continue }
                            changed += 1
                            XCTAssertLessThan(y, 23 * 3, "Etching cannot reach the countdown or metadata")
                            XCTAssertTrue(mirrored ? x >= (190 - 23) * 3 : x < 23 * 3,
                                          "The blossom stays opposite the full header's status badge")
                        }
                    }
                    if color == .black {
                        XCTAssertGreaterThan(changed, 100, "The spare pocket carries an actual five-petal outline")
                    } else {
                        XCTAssertEqual(changed, 0, "White's komi keeps its header pocket undecorated")
                    }
                    for disabled in [try render(spare: true, compact: true),
                                     try render(spare: true, reduced: true),
                                     try render(spare: true, increased: true)] {
                        XCTAssertTrue(stride(from: 3, to: disabled.pixels.count, by: 4)
                            .allSatisfy { disabled.pixels[$0] == 0 },
                            "The spare pocket cannot bypass compact/accessibility suppression")
                    }
                }
            }
        }
    }

    func testSakuraStreamEveningLightingKeepsPlayingGeometryAndStoneIdentity() throws {
        let day = SurroundTheme.sakuraStream.board(for: .light)
        let night = SurroundTheme.sakuraStream.board(for: .dark)
        XCTAssertLessThan(luminance(night.boardColor), luminance(day.boardColor))
        XCTAssertEqual(night.gridStyle, day.gridStyle)
        XCTAssertEqual(night.gridLineScale, day.gridLineScale)
        XCTAssertEqual(night.stoneLightDirection, day.stoneLightDirection)
        for board in [day, night] {
            XCTAssertGreaterThan(contrast(board.black.flat, board.white.flat), 7)
            XCTAssertGreaterThanOrEqual(contrast(board.black.label, board.black.flat), 4.5)
            XCTAssertGreaterThanOrEqual(contrast(board.white.label, board.white.flat), 4.5)
            XCTAssertNotNil(board.black.detailedMarkerCasing)
            XCTAssertNotNil(board.white.detailedMarkerCasing)
        }
        for size in [CGSize(width: 190, height: 190), CGSize(width: 375, height: 375),
                     CGSize(width: 680, height: 680), CGSize(width: 400, height: 260)] {
            for coordinates in [true, false] {
                let light = BoardDepthGeometry(containerSize: size, boardWidth: 19, boardHeight: 19,
                                               showsCoordinates: coordinates, displayScale: 3, depth: day.boardDepth)
                let dark = BoardDepthGeometry(containerSize: size, boardWidth: 19, boardHeight: 19,
                                              showsCoordinates: coordinates, displayScale: 3, depth: night.boardDepth)
                XCTAssertEqual(light, dark, "Changing appearance must not move the grid or its hit targets")
            }
        }
    }

    func testSakuraStreamPorcelainEdgeMatchesArtworkAndPreservesBoardFootprint() throws {
        let fixtures: [(size: CGSize, columns: Int, rows: Int, lift: CGFloat)] = [
            (CGSize(width: 247, height: 247), 19, 19, 0),   // 13 pt compact cells
            (CGSize(width: 266, height: 266), 19, 19, 0),   // 14 pt transition
            (CGSize(width: 304, height: 304), 19, 19, 0.5), // 16 pt partial lift
            (CGSize(width: 760, height: 380), 19, 9, 1),
            (CGSize(width: 380, height: 760), 9, 19, 1),
            (CGSize(width: 740, height: 740), 37, 37, 1)    // Radius limited by the grid margin
        ]
        for scheme: ColorScheme in [.light, .dark] {
            let board = SurroundTheme.sakuraStream.board(for: scheme)
            XCTAssertFalse(board.boardBevel, "The ceramic artwork supplies the face highlight")
            let porcelain = try XCTUnwrap(board.boardDepth)
            XCTAssertEqual(porcelain.edgeStyle, .porcelain)
            var cut = porcelain
            cut.edgeStyle = .cut
            for fixture in fixtures {
                func geometry(_ depth: BoardDepth) -> BoardDepthGeometry {
                    BoardDepthGeometry(containerSize: fixture.size, boardWidth: fixture.columns,
                                       boardHeight: fixture.rows, showsCoordinates: false, displayScale: 3, depth: depth)
                }
                let actual = geometry(porcelain)
                let original = geometry(cut)
                XCTAssertEqual(actual.faceRect, original.faceRect)
                XCTAssertEqual(actual.thickness, original.thickness)
                XCTAssertEqual(actual.cellSize, original.cellSize)
                let artworkRadius = min(actual.faceRect.width, actual.faceRect.height) * 0.015
                XCTAssertEqual(actual.cornerRadius, min(artworkRadius * fixture.lift, actual.cellSize * 0.45),
                               accuracy: 0.001, "Sakura slab silhouette for \(fixture.size)")
            }
        }
    }

    @MainActor
    func testSakuraStreamFramedGlazeKeepsCornerScaleOnRectangularBoards() throws {
        var texture = try XCTUnwrap(SurroundTheme.sakuraStream.board.boardTexture)
        XCTAssertEqual(texture.mapping, .framed)
        // A colored surface makes a cropped rim or a stretched corner visible
        // independently of the contrast of the current artwork.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        texture.image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format).image { renderer in
            for row in 0..<5 {
                for column in 0..<5 {
                    UIColor(red: CGFloat(column) / 4, green: CGFloat(row) / 4, blue: 0.5, alpha: 1).setFill()
                    renderer.fill(CGRect(x: column * 20, y: row * 20, width: 20, height: 20))
                }
            }
        }
        let square = try nativeMaterialPixelsUsingDirectContext(
            Image(uiImage: texture.image).resizable().frame(width: 60, height: 60), scale: 1
        )
        for size in [CGSize(width: 60, height: 60), CGSize(width: 140, height: 60), CGSize(width: 60, height: 140)] {
            let actual = try nativeMaterialPixelsUsingDirectContext(
                texture.framedImage(texture.image, in: size)
                    .frame(width: size.width, height: size.height), scale: 1
            )
            // Corners stay at their distance from the corresponding edges.
            // Midpoint samples check that all four rim strips meet those corners.
            func destination(_ sample: Int, length: Int) -> Int {
                if sample == 30 { return length / 2 }
                return sample < 30 ? sample : length - 60 + sample
            }
            for y in [5, 15, 30, 45, 55] {
                for x in [5, 15, 30, 45, 55] {
                    let source = (y * square.width + x) * 4
                    let target = (destination(y, length: actual.height) * actual.width + destination(x, length: actual.width)) * 4
                    XCTAssertEqual(Array(actual.pixels[target..<target + 4]), Array(square.pixels[source..<source + 4]),
                                   "Glaze sample (\(x), \(y)) on \(size)")
                }
            }
        }
    }

    func testSakuraStreamAssetsKeepSeparateCeramicSurfaceAndEqualStoneFootprints() throws {
        let bundle = Bundle(for: Self.self)
        func image(_ name: String) throws -> UIImage {
            try XCTUnwrap(UIImage(named: name, in: bundle, compatibleWith: nil), name)
        }
        let board = try XCTUnwrap(image("SakuraStreamBoard").cgImage)
        let pixels = try rgbaPixels(for: board, side: 128)
        XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 },
                      "Ivory ceramic is an opaque playing surface")
        try assertEqualAlphaStoneFootprints(StoneImages(
            black: [try image("SakuraStreamBlackStone")],
            white: [try image("SakuraStreamWhiteStone")]
        ))
    }

    /// The transparent canopy layer separates cherry petals from the pink flowers on the bank.
    private func isOpaqueSakuraPetal(_ pixels: [UInt8], at offset: Int) -> Bool {
        let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
        return pixels[offset + 3] >= 250 && red > 205 && red - green > 30 && blue - green > 14
    }

    @MainActor
    func testSakuraStreamHorizontalBoughsConnectBlossomsToTheirStems() throws {
        for (name, growsFromLeft) in [("SakuraStreamArchingBough", true), ("SakuraStreamTrailingBough", false)] {
            let image = try XCTUnwrap(UIImage(named: name, in: Bundle(for: Self.self), compatibleWith: nil), name)
            let width = 320, height = Int((CGFloat(width) * image.size.height / image.size.width).rounded())
            let pixels = try nativeMaterialPixelsUsingDirectContext(
                Image(uiImage: image).resizable().frame(width: CGFloat(width), height: CGFloat(height)), scale: 1
            ).pixels
            let rootColumn = growsFromLeft ? 0 : width - 1
            let rootRows = (0..<height).filter { pixels[($0 * width + rootColumn) * 4 + 3] > 128 }
            XCTAssertGreaterThanOrEqual(rootRows.count, max(3, height / 24), "\(name) needs a visible stem at its root edge")
            let rootRow = try XCTUnwrap(rootRows.dropFirst(rootRows.count / 2).first, name)
            let root = rootRow * width + rootColumn
            var connected = [Bool](repeating: false, count: width * height)
            connected[root] = true
            var frontier = [root]
            while let next = frontier.popLast() {
                let x = next % width, y = next / width
                for row in max(0, y - 1)...min(height - 1, y + 1) {
                    for column in max(0, x - 1)...min(width - 1, x + 1) {
                        let neighbor = row * width + column
                        if !connected[neighbor], pixels[neighbor * 4 + 3] >= 64 {
                            connected[neighbor] = true
                            frontier.append(neighbor)
                        }
                    }
                }
            }
            let ink = connected.indices.filter { pixels[$0 * 4 + 3] >= 64 }
            let petals = ink.filter { isOpaqueSakuraPetal(pixels, at: $0 * 4) }
            XCTAssertGreaterThan(ink.filter { connected[$0] }.count, ink.count * 85 / 100, "\(name) has detached branches")
            XCTAssertGreaterThan(petals.count, width * height / 100, "\(name) needs visible pink petals")
            XCTAssertGreaterThan(petals.filter { connected[$0] }.count, petals.count * 90 / 100,
                                 "\(name) has blossoms disconnected from its stem")
            XCTAssertTrue(ink.contains { index in
                let distance = abs(index % width - rootColumn)
                return connected[index] && distance > width * 9 / 10
            }, "\(name) needs a continuous stem reaching the far tip")
            let columns = (width / 4)..<(width * 3 / 4), rows = (height / 4)..<(height * 3 / 4)
            var gaps = 0
            for y in rows {
                for x in columns where pixels[(y * width + x) * 4 + 3] < 10 { gaps += 1 }
            }
            XCTAssertGreaterThan(gaps, rows.count * columns.count / 6, "\(name) needs open space among its blossoms")
        }
    }

    @MainActor
    func testSakuraStreamBlossomCoverageAcrossViewportSizes() throws {
        func petalCoverage(in size: CGSize, expectsHorizontalBoughs: Bool = false) throws -> Double {
            let canopy = try nativeMaterialPixelsUsingDirectContext(
                SakuraStreamCanopyBehind(size: size, scheme: .light).environment(\.colorScheme, .light),
                scale: 1
            )
            var petalPixels = 0
            for offset in stride(from: 0, to: canopy.pixels.count, by: 4)
                where isOpaqueSakuraPetal(canopy.pixels, at: offset) {
                petalPixels += 1
            }
            if expectsHorizontalBoughs {
                // Both horizontal boughs bring flowers into the open band between the corners.
                let columns = (canopy.width / 3)..<(canopy.width * 2 / 3)
                let top = 0..<(canopy.height / 6), bottom = (canopy.height * 5 / 6)..<canopy.height
                for rows in [top, bottom] {
                    var edgePetals = 0
                    for y in rows {
                        for x in columns where isOpaqueSakuraPetal(canopy.pixels, at: (y * canopy.width + x) * 4) {
                            edgePetals += 1
                        }
                    }
                    XCTAssertGreaterThan(edgePetals, columns.count * rows.count / 100,
                                         "Expected blossoms between the corners at \(size), rows \(rows)")
                }
            }
            return Double(petalPixels) / Double(canopy.width * canopy.height)
        }

        var measurements: [String] = []
        for landscape in [false, true] {
            func viewport(_ short: CGFloat, _ long: CGFloat) -> CGSize {
                landscape ? CGSize(width: long, height: short) : CGSize(width: short, height: long)
            }
            let phone = try petalCoverage(in: viewport(402, 874))
            XCTAssertTrue((0.045...0.10).contains(phone), "Expected the established phone blossom coverage, got \(phone)")
            for size in [viewport(834, 1210), viewport(1032, 1376)] {
                let tablet = try petalCoverage(in: size, expectsHorizontalBoughs: true)
                measurements.append(String(format: "%.0f × %.0f: %.2f%% (phone %.2f%%)",
                                           size.width, size.height, tablet * 100, phone * 100))
                XCTAssertTrue((phone * 0.80...phone * 1.30).contains(tablet),
                              "Blossom coverage at \(size) was \(tablet), compared with \(phone) on the phone")
            }
        }
        let report = XCTAttachment(string: measurements.joined(separator: "\n"))
        report.name = "Sakura Stream petal coverage"
        report.lifetime = .keepAlways
        add(report)
    }

    func testSakuraStreamCanopyPlacementAndBoardSelectionStayBounded() {
        let fixtures: [(CGSize, CGRect)] = [
            (CGSize(width: 402, height: 874), CGRect(x: 0, y: 284, width: 402, height: 402)),
            (CGSize(width: 874, height: 402), CGRect(x: 278, y: 86, width: 308, height: 308)),
            (CGSize(width: 834, height: 1210), CGRect(x: 24, y: 320, width: 786, height: 786)),
            (CGSize(width: 1210, height: 834), CGRect(x: 525, y: 158, width: 584, height: 584)),
            (CGSize(width: 375, height: 548), CGRect(x: 12, y: 168, width: 351, height: 351)),
            (CGSize(width: 1168, height: 976), CGRect(x: 612, y: 220, width: 516, height: 516)),
            (CGSize(width: 176, height: 176), CGRect(x: 38.7, y: 38.7, width: 352, height: 352))
        ]
        for (size, board) in fixtures {
            let main = BoardSceneShadowRegion(bounds: board, isDetailed: true, cellSize: 20)
            let layout = SakuraStreamCanopyLayout(size: size, boards: [main])
            XCTAssertEqual(layout.canopy.size, layout.bottomLeftCanopy.size)
            XCTAssertGreaterThan(layout.leftCanopy.width, layout.canopy.width)
            XCTAssertGreaterThan(layout.bottomRightCanopy.width, layout.canopy.width)
            XCTAssertGreaterThan(layout.canopy.width, 0)
            let viewport = CGRect(origin: .zero, size: size)
            for bough in [layout.canopy, layout.leftCanopy, layout.bottomLeftCanopy, layout.bottomRightCanopy] {
                XCTAssertEqual(bough.width, bough.height)
                XCTAssertFalse(bough.intersection(viewport).isEmpty,
                               "All four corner canopies must remain visible in \(size)")
            }
            XCTAssertLessThan(layout.leftCanopy.minX, 0, "Upper-left bough stem stays outside the left edge")
            XCTAssertLessThan(layout.leftCanopy.minY, 0, "Upper-left bough anchors above the top edge")
            XCTAssertLessThan(layout.bottomLeftCanopy.minX, 0, "Lower-left bough stem stays outside the left edge")
            XCTAssertGreaterThan(layout.canopy.maxX, size.width, "Upper-right bough stem stays outside the right edge")
            XCTAssertLessThan(layout.canopy.minY, 0, "Upper-right bough anchors in the top-right corner above the top edge")
            XCTAssertGreaterThan(layout.bottomRightCanopy.maxX, size.width, "Lower-right bough stem stays outside the right edge")
            XCTAssertGreaterThan(layout.bottomLeftCanopy.maxY, size.height, "Lower-left stem stays below the bottom edge")
            XCTAssertGreaterThan(layout.bottomRightCanopy.maxY, size.height, "Lower-right stem stays below the bottom edge")
            XCTAssertTrue((5...10).contains(layout.blurRadius))
            XCTAssertTrue((7...16).contains(layout.groundBlurRadius))
            XCTAssertGreaterThan(layout.groundBlurRadius, layout.blurRadius,
                                 "Riverbed/ground penumbra is softer than raised board/UI shadow")
            if layout.leftShadowCanopy.minX >= -layout.blurRadius * 3
                || layout.bottomLeftShadowCanopy.minX >= -layout.blurRadius * 3
                || layout.rightShadowCanopy.minY >= -layout.blurRadius * 3 {
                XCTAssertGreaterThan(layout.leftShadowFeather, 0.15,
                                     "Far-shifted tall-tree shadows must feather cut leading/top stem edges at \(size)")
                XCTAssertGreaterThan(layout.shadowEdgeFeather, 0.15,
                                     "Far-shifted tall-tree shadows must feather cut leading/top stem edges at \(size)")
            }
            XCTAssertGreaterThan(layout.bottomLeftShadowCanopy.maxY, size.height + layout.blurRadius * 3,
                                 "Blurred lower-left shadow root must stay off-screen bottom at \(size)")
            XCTAssertGreaterThan(layout.rightShadowCanopy.maxX, size.width + layout.blurRadius * 3,
                                 "Blurred upper-right shadow root must stay off-screen right at \(size)")
            XCTAssertGreaterThan(layout.bottomRightShadowCanopy.maxX, size.width + layout.blurRadius * 3,
                                 "Blurred lower-right shadow root must stay off-screen right at \(size)")
            XCTAssertGreaterThan(layout.bottomRightShadowCanopy.maxY, size.height + layout.blurRadius * 3,
                                 "Blurred lower-right shadow root must stay off-screen bottom at \(size)")
            for (bough, fgShadow, groundShadow) in [
                (layout.leftCanopy, layout.leftShadowCanopy, layout.leftGroundShadowCanopy),
                (layout.canopy, layout.rightShadowCanopy, layout.rightGroundShadowCanopy),
                (layout.bottomLeftCanopy, layout.bottomLeftShadowCanopy, layout.bottomLeftGroundShadowCanopy),
                (layout.bottomRightCanopy, layout.bottomRightShadowCanopy, layout.bottomRightGroundShadowCanopy)
            ] {
                XCTAssertGreaterThan(fgShadow.midX, bough.midX)
                XCTAssertGreaterThan(fgShadow.midY, bough.midY)
                let fgOffset = hypot(fgShadow.midX - bough.midX, fgShadow.midY - bough.midY)
                let groundOffset = hypot(groundShadow.midX - bough.midX, groundShadow.midY - bough.midY)
                XCTAssertGreaterThan(fgOffset, bough.width * 0.45,
                                     "Tall-tree overhead boughs must cast far-displaced shadows, never hugging the foliage at \(size)")
                XCTAssertGreaterThan(groundOffset, fgOffset,
                                     "Ground/water plane sits further below the tree crown than the raised ceramic board at \(size)")
            }
            let overlap = layout.leftShadowCanopy.intersection(board.intersection(CGRect(origin: .zero, size: size)))
            XCTAssertGreaterThan(overlap.width, 40, "Upper-left canopy shade must reach the main board at \(size)")
            XCTAssertGreaterThan(overlap.height, 40, "Upper-left canopy shade must reach the main board at \(size)")
            let compact = BoardSceneShadowRegion(bounds: CGRect(origin: .zero, size: size),
                                                 isDetailed: false, cellSize: 13)
            let selected = SakuraStreamBoardCanopyLayout(size: size, boards: [compact, main])
            XCTAssertEqual(selected.board, main, "A larger compact board cannot receive the projection")
        }
        for size in [CGSize.zero, CGSize(width: -1, height: 400),
                     CGSize(width: CGFloat.infinity, height: 400), CGSize(width: 400, height: CGFloat.nan)] {
            let layout = SakuraStreamCanopyLayout(size: size)
            XCTAssertEqual(layout.canopy, .zero)
            XCTAssertEqual(layout.leftCanopy, .zero)
            XCTAssertEqual(layout.bottomLeftCanopy, .zero)
            XCTAssertEqual(layout.bottomRightCanopy, .zero)
            XCTAssertEqual(layout.leftGroundShadowCanopy, .zero)
            XCTAssertEqual(layout.rightGroundShadowCanopy, .zero)
            XCTAssertEqual(layout.bottomLeftGroundShadowCanopy, .zero)
            XCTAssertEqual(layout.bottomRightGroundShadowCanopy, .zero)
            XCTAssertEqual(layout.leftShadowCanopy, .zero)
            XCTAssertEqual(layout.rightShadowCanopy, .zero)
            XCTAssertEqual(layout.bottomLeftShadowCanopy, .zero)
            XCTAssertEqual(layout.bottomRightShadowCanopy, .zero)
            XCTAssertEqual(layout.groundBlurRadius, 0)
            XCTAssertEqual(layout.blurRadius, 0)
            XCTAssertEqual(layout.shadowEdgeFeather, 0)
            XCTAssertTrue([layout.size.width, layout.size.height].allSatisfy(\.isFinite))
        }
    }

    @MainActor
    func testSakuraStreamCanopyMasksProtectContentAndEveryOtherBoard() throws {
        let size = CGSize(width: 240, height: 260)
        let main = BoardSceneShadowRegion(bounds: CGRect(x: 20, y: 40, width: 190, height: 190),
                                          cornerRadius: 8, isDetailed: true, cellSize: 20)
        let compact = BoardSceneShadowRegion(bounds: CGRect(x: 180, y: 70, width: 50, height: 45),
                                             isDetailed: false, cellSize: 7)
        let preview = BoardSceneShadowRegion(bounds: CGRect(x: 130, y: 45, width: 50, height: 50),
                                             isDetailed: true, cellSize: 14)
        let raster = try nativeMaterialPixels(Color.black
            .mask(SakuraStreamBoardCanopyMask(boards: [main, compact, preview]))
            .frame(width: size.width, height: size.height))
        var visibleOnBoard = 0
        var visibleOutsideBoard = 0
        var violations: [String: (count: Int, maxAlpha: UInt8, firstPoint: CGPoint)] = [:]
        func record(_ reason: String, at point: CGPoint, alpha: UInt8) {
            let previous = violations[reason]
            violations[reason] = ((previous?.count ?? 0) + 1,
                                  max(previous?.maxAlpha ?? 0, alpha), previous?.firstPoint ?? point)
        }
        for y in 0..<raster.height {
            for x in 0..<raster.width {
                let alpha = raster.pixels[(y * raster.width + x) * 4 + 3]
                guard alpha > 0 else { continue }
                let point = CGPoint(x: (CGFloat(x) + 0.5) / 3, y: (CGFloat(y) + 0.5) / 3)
                if compact.bounds.insetBy(dx: 1, dy: 1).contains(point) {
                    record("inside compact board", at: point, alpha: alpha)
                } else if preview.bounds.insetBy(dx: 1, dy: 1).contains(point) {
                    record("inside other detailed board", at: point, alpha: alpha)
                } else if main.bounds.contains(point) {
                    visibleOnBoard += 1
                } else {
                    visibleOutsideBoard += 1
                }
            }
        }
        XCTAssertTrue(violations.isEmpty, "Shadow mask board-exclusion violations: \(violations)")
        XCTAssertGreaterThan(visibleOnBoard, 500, "The main detailed board receives blossom shadows")
        XCTAssertGreaterThan(visibleOutsideBoard, 500, "Clocks and panels outside the board also receive blossom shadows")
        func alpha(_ x: Int, _ y: Int) -> UInt8 { raster.pixels[((y * 3) * raster.width + x * 3) * 4 + 3] }
        XCTAssertEqual(alpha(120, 4), 0, "Status bar strip stays clear at the top edge")
        XCTAssertEqual(alpha(120, 120), 255, "Gameplay and control band receives full mask coverage")
        for cell: CGFloat in [7, 13, 13.999] {
            let board = BoardSceneShadowRegion(bounds: main.bounds, isDetailed: true, cellSize: cell)
            let raster = try nativeMaterialPixels(Color.black
                .mask(SakuraStreamBoardCanopyMask(boards: [board]))
                .frame(width: size.width, height: size.height))
            var compactLeak = 0
            for y in 0..<raster.height {
                for x in 0..<raster.width {
                    let point = CGPoint(x: (CGFloat(x) + 0.5) / 3, y: (CGFloat(y) + 0.5) / 3)
                    if main.bounds.insetBy(dx: 1, dy: 1).contains(point),
                       raster.pixels[(y * raster.width + x) * 4 + 3] != 0 {
                        compactLeak += 1
                    }
                }
            }
            XCTAssertEqual(compactLeak, 0, "Actual cell size independently enforces the 14 pt solid contract")
        }
    }

    @MainActor
    func testSakuraStreamCanopyProjectionUsesArtAndSuppressesAccessibilityAndSmallBoards() throws {
        let bundle = Bundle(for: Self.self)
        let rightAsset = try XCTUnwrap(UIImage(named: "SakuraStreamCanopy", in: bundle, compatibleWith: nil))
        let leftAsset = try XCTUnwrap(UIImage(named: "SakuraStreamCanopyLeft", in: bundle, compatibleWith: nil))
        let bottomLeftAsset = try XCTUnwrap(UIImage(named: "SakuraStreamCanopyBottomLeft", in: bundle, compatibleWith: nil))
        let bottomRightAsset = try XCTUnwrap(UIImage(named: "SakuraStreamCanopyBottomRight", in: bundle, compatibleWith: nil))
        for asset in [rightAsset, leftAsset, bottomLeftAsset, bottomRightAsset] {
            XCTAssertEqual(asset.cgImage?.width, rightAsset.cgImage?.width)
            XCTAssertEqual(asset.cgImage?.height, rightAsset.cgImage?.height)
            let art = try rgbaPixels(for: XCTUnwrap(asset.cgImage), side: 128)
            XCTAssertTrue(stride(from: 3, to: art.count, by: 4).contains { art[$0] == 0 },
                          "Each canopy sprite must preserve transparent surroundings")
            XCTAssertTrue(stride(from: 3, to: art.count, by: 4).contains { art[$0] > 240 },
                          "Core blossoms remain opaque in the background foliage layer")
        }
        let opacityProbe = try nativeMaterialPixelsUsingDirectContext(Color.black.frame(width: 20, height: 20).opacity(0), scale: 1)
        XCTAssertTrue(stride(from: 3, to: opacityProbe.pixels.count, by: 4).allSatisfy { opacityProbe.pixels[$0] == 0 },
                      "Native renderer must preserve zero opacity before assessing projection suppression")
        let size = CGSize(width: 402, height: 874)
        var maxAlphaByScheme: [ColorScheme: UInt8] = [:]
        for scheme: ColorScheme in [.light, .dark] {
            func render(cell: CGFloat = 20, detailed: Bool = true, reduced: Bool = false,
                        increased: Bool = false) throws -> [UInt8] {
                let board = BoardSceneShadowRegion(bounds: CGRect(x: 0, y: 284, width: 402, height: 402),
                                                  isDetailed: detailed, cellSize: cell)
                let projection = SakuraStreamCanopyProjection(size: size, scheme: scheme,
                    boards: [board], reduceTransparency: reduced, contrast: increased ? .increased : .standard)
                let expected = !reduced && !increased
                XCTAssertEqual(projection.allowsProjection, expected)
                return try nativeMaterialPixelsUsingDirectContext(projection
                    .frame(width: size.width, height: size.height).environment(\.colorScheme, scheme), scale: 1).pixels
            }
            let board = BoardSceneShadowRegion(bounds: CGRect(x: 0, y: 284, width: 402, height: 402),
                                               isDetailed: true, cellSize: 20)
            let shadows = try nativeMaterialPixelsUsingDirectContext(
                SakuraStreamCanopyShadowProjection(size: size, scheme: scheme, boards: [board], isEnabled: true)
                    .frame(width: size.width, height: size.height), scale: 1).pixels
            let alpha = stride(from: 3, to: shadows.count, by: 4).map { shadows[$0] }
            let peak = alpha.max() ?? 0
            maxAlphaByScheme[scheme] = peak
            XCTAssertGreaterThanOrEqual(peak, scheme == .dark ? 20 : 28,
                                        "Blossom shadows must be clearly visible across board and controls")
            XCTAssertLessThanOrEqual(peak, 52, "Foreground blossom shadows stay soft enough to preserve contrast")
            for (mode, solid) in [("Reduce Transparency", try render(reduced: true)),
                                  ("Increased Contrast", try render(increased: true))] {
                let visible = stride(from: 3, to: solid.count, by: 4).filter { solid[$0] != 0 }
                XCTAssertTrue(visible.isEmpty, "\(scheme), \(mode): accessibility must suppress foreground shadows")
            }
            for (mode, compactPixels) in [("13 pt cell", try render(cell: 13)),
                                          ("compact metadata", try render(detailed: false))] {
                var boardLeak = 0
                var controlCast = 0
                for y in 285..<685 {
                    for x in 1..<401 where compactPixels[(y * Int(size.width) + x) * 4 + 3] != 0 {
                        boardLeak += 1
                    }
                }
                for y in 115..<265 {
                    for x in 10..<392 where compactPixels[(y * Int(size.width) + x) * 4 + 3] != 0 {
                        controlCast += 1
                    }
                }
                XCTAssertEqual(boardLeak, 0, "\(scheme), \(mode): compact board interior must stay completely unshaded")
                XCTAssertGreaterThan(controlCast, 500, "\(scheme), \(mode): surrounding controls retain scene shadow")
            }
        }
        XCTAssertLessThan(try XCTUnwrap(maxAlphaByScheme[.dark]), try XCTUnwrap(maxAlphaByScheme[.light]),
                          "Evening twilight attenuates board dapple compared with daytime sun")
    }

    @MainActor
    func testSakuraStreamCanopyRimTouchesOnlyTheMainBoardMargin() throws {
        // The lower-right bough meets the board in the iPad landscape game.
        let size = CGSize(width: 1210, height: 834)
        let main = BoardSceneShadowRegion(bounds: CGRect(x: 531, y: 160, width: 572, height: 576),
                                         cornerRadius: 8, isDetailed: true, cellSize: 30, frontDepth: 4)
        func render(_ boards: [BoardSceneShadowRegion]) throws -> (painted: [CGPoint], opaque: [CGPoint]) {
            let layer = SakuraStreamCanopyRim(size: size, scheme: .light, boards: boards, isEnabled: true)
            let raster = try nativeMaterialPixelsUsingDirectContext(layer.frame(width: size.width, height: size.height), scale: 1)
            var painted = [CGPoint](), opaque = [CGPoint]()
            for i in stride(from: 3, to: raster.pixels.count, by: 4) where raster.pixels[i] != 0 {
                let pixel = i / 4
                let point = CGPoint(x: CGFloat(pixel % raster.width) + 0.5, y: CGFloat(pixel / raster.width) + 0.5)
                painted.append(point)
                if raster.pixels[i] > 180 { opaque.append(point) }
            }
            return (painted, opaque)
        }
        let actual = try render([main])
        let face = CGRect(x: main.bounds.minX, y: main.bounds.minY,
                          width: main.bounds.width, height: main.bounds.height - main.frontDepth)
        let core = face.insetBy(dx: main.cellSize / 2, dy: main.cellSize / 2)
        XCTAssertFalse(actual.painted.contains(where: core.contains), "Every playing intersection stays clear")
        XCTAssertTrue(actual.painted.allSatisfy(main.bounds.insetBy(dx: -1, dy: -1).contains),
                      "The foreground copy is confined to the slab")
        let petal = try XCTUnwrap(actual.opaque.first, "Actual canopy artwork visibly crosses the ceramic perimeter")
        let hole = CGRect(x: petal.x - 12, y: petal.y - 12, width: 24, height: 24)
        for previewCell: CGFloat in [13, 20] {
            let preview = BoardSceneShadowRegion(bounds: hole, cellSize: previewCell)
            let masked = try render([main, preview])
            XCTAssertFalse(masked.painted.contains(where: hole.insetBy(dx: 1, dy: 1).contains),
                           "Every other board excludes the physical bough where it would cover a visible petal")
        }
        var compact = main
        compact.cellSize = 13
        XCTAssertTrue(try render([compact]).painted.isEmpty)
        for (reduced, contrast): (Bool, ColorSchemeContrast) in [(true, .standard), (false, .increased)] {
            let layer = SakuraStreamCanopyProjection(size: size, scheme: .light, boards: [main],
                                                      reduceTransparency: reduced, contrast: contrast)
            let raster = try nativeMaterialPixelsUsingDirectContext(layer.frame(width: size.width, height: size.height), scale: 1)
            XCTAssertFalse(stride(from: 3, to: raster.pixels.count, by: 4).contains { raster.pixels[$0] != 0 },
                           "Accessibility suppression clears the rim and the raised shadow together")
        }
    }

    @MainActor
    func testSakuraStreamLandscapeShadowsReachBoardWhileKeepingClocksAndPreviewsClear() throws {
        let size = CGSize(width: 874, height: 402)
        let main = BoardSceneShadowRegion(bounds: CGRect(x: 278, y: 86, width: 308, height: 308),
                                         cornerRadius: 2, isDetailed: true, cellSize: 16)
        let compact = BoardSceneShadowRegion(bounds: CGRect(x: 310, y: 170, width: 70, height: 80),
                                            isDetailed: true, cellSize: 13)
        let preview = BoardSceneShadowRegion(bounds: CGRect(x: 295, y: 98, width: 65, height: 65),
                                            isDetailed: true, cellSize: 14)
        for scheme: ColorScheme in [.light, .dark] {
            func render(_ boards: [BoardSceneShadowRegion], enabled: Bool = true) throws
                -> (pixels: [UInt8], width: Int, height: Int) {
                try nativeMaterialPixelsUsingDirectContext(SakuraStreamCanopyShadowProjection(size: size, scheme: scheme,
                    boards: boards, isEnabled: enabled).frame(width: size.width, height: size.height), scale: 1)
            }
            func visibleCount(_ raster: (pixels: [UInt8], width: Int, height: Int), in rect: CGRect) -> Int {
                var count = 0
                for y in 0..<raster.height {
                    for x in 0..<raster.width where rect.contains(CGPoint(x: x, y: y)) {
                        if raster.pixels[(y * raster.width + x) * 4 + 3] > 0 { count += 1 }
                    }
                }
                return count
            }
            let base = try render([main])
            let alpha = stride(from: 3, to: base.pixels.count, by: 4).map { base.pixels[$0] }
            XCTAssertGreaterThanOrEqual(alpha.max() ?? 0, scheme == .dark ? 20 : 28)
            XCTAssertLessThanOrEqual(alpha.max() ?? 255, 52, "Overlapping casts remain composited without stacking")
            XCTAssertGreaterThan(visibleCount(base, in: CGRect(x: 96, y: 74, width: 176, height: 226)), 500,
                                 "Left clock and player column receive visible blossom shadows")
            XCTAssertGreaterThan(visibleCount(base, in: main.bounds.insetBy(dx: 16, dy: 16)), 500,
                                 "Upper-left sakura crown casts recognizable blossom shadows onto the detailed board")
            for hole in [compact, preview] {
                XCTAssertGreaterThan(visibleCount(base, in: hole.bounds.insetBy(dx: 1, dy: 1)), 30,
                                     "Each exclusion must overlap real dapple pixels in this fixture")
            }
            let masked = try render([main, compact, preview])
            for hole in [compact, preview] {
                XCTAssertEqual(visibleCount(masked, in: hole.bounds.insetBy(dx: 1, dy: 1)), 0,
                               "Compact and secondary detailed boards exclude the entire cast")
            }
            let disabled = try render([main], enabled: false)
            XCTAssertEqual(visibleCount(disabled, in: CGRect(origin: .zero, size: size)), 0,
                           "Accessibility suppression must clear the standalone shadow layer")
        }
    }

    @MainActor
    func testSakuraStreamCanopyRendererClearsBetweenVisibilityStates() throws {
        let orientation = VStack(spacing: 0) {
            Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1).frame(width: 20, height: 10)
            Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1).frame(width: 20, height: 10)
        }
        for scale: CGFloat in [1, 3] {
            let raster = try nativeMaterialPixelsUsingDirectContext(orientation, scale: scale)
            XCTAssertEqual(raster.width, Int(20 * scale))
            XCTAssertEqual(raster.height, Int(20 * scale))
            func pixel(_ x: Int, _ y: Int) -> [UInt8] {
                let start = (Int(CGFloat(y) * scale) * raster.width + Int(CGFloat(x) * scale)) * 4
                return Array(raster.pixels[start..<(start + 4)])
            }
            XCTAssertEqual(pixel(10, 5), [255, 0, 0, 255], "Direct context preserves the top row and RGBA order")
            XCTAssertEqual(pixel(10, 15), [0, 0, 255, 255], "Direct context preserves the bottom row")
        }
        let size = CGSize(width: 874, height: 402)
        let board = BoardSceneShadowRegion(bounds: CGRect(x: 278, y: 86, width: 308, height: 308),
                                          cornerRadius: 2, isDetailed: true, cellSize: 16)
        for enabled in [false, true, false, true] {
            let raster = try nativeMaterialPixelsUsingDirectContext(
                SakuraStreamCanopyShadowProjection(size: size, scheme: .light,
                    boards: [board], isEnabled: enabled).frame(width: size.width, height: size.height), scale: 1)
            let visible = stride(from: 3, to: raster.pixels.count, by: 4).filter { raster.pixels[$0] > 0 }.count
            if enabled { XCTAssertGreaterThan(visible, 300) }
            else { XCTAssertEqual(visible, 0, "An empty projection must not reuse the preceding rendered frame") }
        }
    }

    func testSakuraStreamSceneCoversEveryViewportWithoutStretching() {
        for size in [CGSize(width: 375, height: 548), CGSize(width: 375, height: 667),
                     CGSize(width: 402, height: 874), CGSize(width: 874, height: 402),
                     CGSize(width: 820, height: 1180), CGSize(width: 1180, height: 820),
                     CGSize(width: 540, height: 720), CGSize(width: 720, height: 540),
                     CGSize(width: 976, height: 1168), CGSize(width: 1168, height: 976),
                     CGSize(width: 900, height: 600), CGSize(width: 1440, height: 760),
                     CGSize(width: 176, height: 176)] {
            let layout = SakuraStreamSceneLayout(size: size)
            let frame = layout.imageFrame
            XCTAssertEqual(layout.size, size)
            XCTAssertEqual(layout.composition, size.width > size.height ? .landscape : .portrait)
            XCTAssertLessThanOrEqual(frame.minX, 0.0001)
            XCTAssertLessThanOrEqual(frame.minY, 0.0001)
            XCTAssertGreaterThanOrEqual(frame.maxX + 0.0001, size.width)
            XCTAssertGreaterThanOrEqual(frame.maxY + 0.0001, size.height)
            let source = layout.composition.sourceSize
            XCTAssertEqual(frame.width / source.width, frame.height / source.height, accuracy: 0.000001,
                           "Ceramic surroundings, blossoms and water must keep their proportions")
            XCTAssertEqual(min(frame.width / size.width, frame.height / size.height), 1, accuracy: 0.000001)
        }
        for size in [CGSize.zero, CGSize(width: 0, height: 300), CGSize(width: 300, height: 0),
                     CGSize(width: -1, height: 300), CGSize(width: CGFloat.infinity, height: 300),
                     CGSize(width: 300, height: CGFloat.nan)] {
            let layout = SakuraStreamSceneLayout(size: size)
            XCTAssertEqual(layout.imageFrame, .zero)
            XCTAssertTrue(layout.size.width.isFinite && layout.size.height.isFinite)
            XCTAssertGreaterThanOrEqual(layout.size.width, 0)
            XCTAssertGreaterThanOrEqual(layout.size.height, 0)
        }
    }

    func testSakuraStreamWaterStaysClearOfDefaultBoards() {
        // Default board origins measured in the native offline layout audit.
        // The small phone and closed Duo are the tightest leading-edge gaps.
        let viewports: [(size: CGSize, boardStart: CGFloat)] = [
            (CGSize(width: 375, height: 667), 148),
            (CGSize(width: 375, height: 549), 204),
            (CGSize(width: 375, height: 1000), 232),
            (CGSize(width: 834, height: 1210), 320),
            (CGSize(width: 466, height: 678), 168),
            (CGSize(width: 678, height: 466), 150),
            (CGSize(width: 669, height: 951), 508),
            (CGSize(width: 951, height: 669), 368)
        ]
        for (size, boardStart) in viewports {
            let layout = SakuraStreamSceneLayout(size: size)
            let frame = layout.imageFrame
            // Maximum water extents in the source plates along their cropped axes.
            let waterEnd = layout.composition == .portrait
                ? frame.minY + frame.height * 0.21
                : frame.minX + frame.width * 0.208
            XCTAssertGreaterThan(waterEnd, 0, "The stream remains visible at \(size)")
            XCTAssertLessThanOrEqual(waterEnd, boardStart - 7,
                                     "Default board must stay on dry ground at \(size)")
        }
        // Near-square picker/window crops must not expand the wet band.
        for size in [CGSize(width: 176, height: 176), CGSize(width: 600, height: 601),
                     CGSize(width: 601, height: 600)] {
            let layout = SakuraStreamSceneLayout(size: size)
            let frame = layout.imageFrame
            if layout.composition == .portrait {
                XCTAssertLessThanOrEqual(frame.minY + frame.height * 0.21, size.height * 0.21 + 0.001)
            } else {
                XCTAssertLessThanOrEqual(frame.minX + frame.width * 0.208, size.width * 0.222 + 0.001)
            }
        }
    }

    func testSakuraStreamSceneAssetsAreOpaqueAndMatchTheirComposition() throws {
        let bundle = Bundle(for: Self.self)
        for composition in SakuraStreamSceneLayout.Composition.allCases {
            let image = try XCTUnwrap(UIImage(named: composition.assetName, in: bundle, compatibleWith: nil))
            let source = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(CGFloat(source.width), composition.sourceSize.width)
            XCTAssertEqual(CGFloat(source.height), composition.sourceSize.height)
            let pixels = try rgbaPixels(for: source, side: 128)
            XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 },
                          "The overhead riverside scene must fill the viewport continuously")
        }
    }

    @MainActor
    func testSakuraStreamSceneDimsWithSystemAppearance() throws {
        func brightness(_ scheme: ColorScheme) throws -> Double {
            let rendered = try nativeMaterialPixels(GameDetailBackdrop()
                .environment(\.surroundTheme, .sakuraStream)
                .environment(\.colorScheme, scheme)
                .frame(width: 200, height: 360))
            let rows = (rendered.height / 2 - 30)..<(rendered.height / 2 + 30)
            var sum = 0.0
            for y in rows {
                for x in 0..<rendered.width {
                    let offset = (y * rendered.width + x) * 4
                    sum += (0.2126 * Double(rendered.pixels[offset])
                            + 0.7152 * Double(rendered.pixels[offset + 1])
                            + 0.0722 * Double(rendered.pixels[offset + 2])) / 255
                }
            }
            return sum / Double(rows.count * rendered.width)
        }
        let day = try brightness(.light), night = try brightness(.dark)
        XCTAssertGreaterThan(day, 0.1)
        XCTAssertLessThan(night, day * 0.8, "Evening subdues the same stream without changing its crop")

        // Home, Settings, Public games and Game history use this shared backdrop.
        // Sample opaque canopy petals by location so pink groundcover cannot pass
        // an integration check or be mistaken for an overhanging branch.
        typealias Region = (columns: Range<Int>, rows: Range<Int>)
        func checkCanopies(size: CGSize, corners: [Region], openings: [Region]) throws {
            let canopy = try nativeMaterialPixelsUsingDirectContext(
                SakuraStreamCanopyBehind(size: size, scheme: .light).environment(\.colorScheme, .light), scale: 1
            )
            func backdrop(_ scheme: ColorScheme) throws -> [UInt8] {
                try nativeMaterialPixelsUsingDirectContext(
                    GameDetailBackdrop()
                        .environment(\.surroundTheme, .sakuraStream)
                        .environment(\.colorScheme, scheme)
                        .frame(width: size.width, height: size.height), scale: 1
                ).pixels
            }
            let day = try backdrop(.light), night = try backdrop(.dark)
            func luma(_ pixels: [UInt8], _ offset: Int) -> Double {
                0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1]) + 0.0722 * Double(pixels[offset + 2])
            }
            for (columns, rows) in corners {
                var corePetals = 0, interiorPetals = 0, matchingPetals = 0
                var dayLuma = 0.0, nightLuma = 0.0
                for y in rows {
                    for x in columns {
                        let i = (y * canopy.width + x) * 4
                        guard isOpaqueSakuraPetal(canopy.pixels, at: i) else { continue }
                        corePetals += 1
                        // Older systems add a scrim at the screen edges. Compare
                        // independent renders only where the petals are unobscured.
                        guard y >= 92, y < canopy.height - 76 else { continue }
                        interiorPetals += 1
                        let r = Int(canopy.pixels[i]), g = Int(canopy.pixels[i + 1]), b = Int(canopy.pixels[i + 2])
                        if abs(r - Int(day[i])) <= 10 && abs(g - Int(day[i + 1])) <= 10 && abs(b - Int(day[i + 2])) <= 10 {
                            matchingPetals += 1
                        }
                        dayLuma += luma(day, i)
                        nightLuma += luma(night, i)
                    }
                }
                let corner = "\(size), x \(columns), y \(rows)"
                XCTAssertGreaterThan(corePetals, 1200, "Blooming bough is visible at \(corner)")
                XCTAssertGreaterThan(interiorPetals, 50, "Petals reach beyond the edge scrim at \(corner)")
                XCTAssertGreaterThan(matchingPetals, interiorPetals * 9 / 10,
                                     "The shared backdrop renders the canopy's own petals at \(corner)")
                XCTAssertLessThan(nightLuma, dayLuma * 0.72, "Evening subdues the bough at \(corner)")
            }

            // The separate canopy layer lets its translucent ground shadows pass
            // while exposing any solid flowers, twigs or leaves in these gaps.
            for (columns, rows) in openings {
                var opaquePixels = 0
                for y in rows {
                    for x in columns where canopy.pixels[(y * canopy.width + x) * 4 + 3] > 200 {
                        opaquePixels += 1
                    }
                }
                XCTAssertLessThan(opaquePixels, 250, "Keep the bank and board clear at \(size), x \(columns), y \(rows)")
            }
        }

        try checkCanopies(size: CGSize(width: 402, height: 874),
                          corners: [(0..<201, 0..<200), (201..<402, 0..<200),
                                    (0..<201, 680..<874), (201..<402, 680..<874)],
                          openings: [(175..<195, 34..<94), (0..<402, 215..<660), (170..<226, 706..<748)])
        try checkCanopies(size: CGSize(width: 874, height: 402),
                          corners: [(0..<220, 0..<170), (620..<874, 0..<140),
                                    (0..<220, 255..<402), (680..<874, 240..<402)],
                          openings: [(0..<160, 185..<240), (620..<874, 145..<225)])
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
        XCTAssertEqual(SurroundTheme.current(storedID: "christmasKeepsakes"), .christmasKeepsakes)
        XCTAssertEqual(SurroundTheme.current(storedID: "paperBlossoms"), .paperBlossoms)
        XCTAssertEqual(SurroundTheme.current(storedID: "sakuraStream"), .sakuraStream)
        XCTAssertEqual(SurroundTheme.current(storedID: "whittledWoodland"), .whittledWoodland)
        XCTAssertEqual(SurroundTheme.current(storedID: "reefLight"), .reefLight)
        XCTAssertEqual(SurroundTheme.current(storedID: "koiPond"), .koiPond)
        XCTAssertEqual(SurroundTheme.current(storedID: "goldenCrumb"), .goldenCrumb)
        #else
        XCTAssertEqual(SurroundTheme.current(storedID: "nebulaPearl"), .nebulaPearl)
        XCTAssertEqual(SurroundTheme.current(storedID: "rakedGarden"), .rakedGarden)
        XCTAssertEqual(SurroundTheme.current(storedID: "surroundStudio"), .surroundStudio)
        XCTAssertEqual(SurroundTheme.current(storedID: "frostPine"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: "feltMeadow"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: "nightGarden"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: "christmasKeepsakes"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: "paperBlossoms"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: "sakuraStream"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: "whittledWoodland"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: "reefLight"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: "koiPond"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: "goldenCrumb"), .standard)
        #endif
    }

    /// Classic and three scenes ship, in the pickers' order; Debug builds
    /// append the unreleased themes.
    func testPickersOfferTheReleasedThemesFirst() {
        XCTAssertEqual(SurroundTheme.released, [.standard, .surroundStudio, .rakedGarden, .nebulaPearl])
        let unreleased: [SurroundTheme] = [.frostPine, .feltMeadow, .nightGarden, .christmasKeepsakes,
                                          .paperBlossoms, .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain, .sakuraStream, .whittledWoodland, .reefLight, .koiPond, .goldenCrumb]
        XCTAssertEqual(SurroundTheme.allCases.filter(\.isDebugOnly), unreleased)
        #if DEBUG
        XCTAssertEqual(SurroundTheme.available, SurroundTheme.released + unreleased)
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
    /// Debug-only theme's art, sounds and thumbnail live there and a released
    /// theme's never do. Releasing a theme moves its assets and thumbnail
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
        func assets(in catalog: URL) -> Set<String> {
            let items = FileManager.default.enumerator(at: catalog, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL } ?? []
            return Set(items.filter { ["imageset", "dataset"].contains($0.pathExtension) }
                .map { $0.deletingPathExtension().lastPathComponent })
        }
        // Theme art is named after its theme: frostPine's is FrostPine….
        func assetTheme(of asset: String) -> SurroundTheme? {
            SurroundTheme.allCases.first { theme in
                asset == theme.previewImageName
                    || asset.hasPrefix(theme.rawValue.prefix(1).uppercased() + theme.rawValue.dropFirst())
                    || asset.hasPrefix("StoneSound-\(theme.rawValue)-")
                    || asset.hasPrefix("StoneCapture-\(theme.rawValue)-")
            }
        }
        let shipping = assets(in: shippingCatalog)
        let debug = assets(in: debugCatalog)
        for asset in shipping {
            XCTAssertFalse(assetTheme(of: asset)?.isDebugOnly ?? false, "\(asset) belongs in DebugThemes.xcassets")
        }
        for asset in debug {
            XCTAssertTrue(assetTheme(of: asset)?.isDebugOnly ?? false, "\(asset) belongs in Assets.xcassets")
        }
        for theme in SurroundTheme.allCases {
            let expected = theme.isDebugOnly ? debug : shipping
            XCTAssert(expected.contains(theme.previewImageName),
                      "\(theme)'s thumbnail is in the wrong catalog")
            for color: StoneColor in [.black, .white] {
                for variation in StonePlacementSoundPlayer.variations {
                    let name = StonePlacementSoundPlayer.assetName(theme: theme, color: color, variation: variation)
                    // Visual variants can share an existing sound bank. Its
                    // catalog follows the bank's owner, not the active scene.
                    let soundOwner = try XCTUnwrap(assetTheme(of: name), "\(name) has no owning theme")
                    let soundCatalog = soundOwner.isDebugOnly ? debug : shipping
                    let otherSoundCatalog = soundOwner.isDebugOnly ? shipping : debug
                    XCTAssertTrue(soundCatalog.contains(name), "\(name) is missing from its theme's catalog")
                    XCTAssertFalse(otherSoundCatalog.contains(name), "\(name) is also in the wrong catalog")
                    for tier in StonePlacementSoundPlayer.CaptureTier.allCases {
                        let capture = StonePlacementSoundPlayer.captureAssetName(theme: theme, color: color,
                                                                                tier: tier, variation: variation)
                        let captureOwner = try XCTUnwrap(assetTheme(of: capture), "\(capture) has no owning theme")
                        let captureCatalog = captureOwner.isDebugOnly ? debug : shipping
                        let otherCaptureCatalog = captureOwner.isDebugOnly ? shipping : debug
                        XCTAssertTrue(captureCatalog.contains(capture), "\(capture) is missing from its theme's catalog")
                        XCTAssertFalse(otherCaptureCatalog.contains(capture), "\(capture) is also in the wrong catalog")
                    }
                }
            }
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

    func testChristmasKeepsakesPaletteAndGlassMarkersAdaptToAppearance() throws {
        let theme = SurroundTheme.christmasKeepsakes
        XCTAssertTrue(theme.isDebugOnly)
        XCTAssertTrue(theme.hasScene)
        XCTAssertNil(theme.colorScheme, "Christmas Keepsakes follows system appearance")
        assertAdaptiveColorsFollowRepeatedTraitChanges(theme)
        for scheme: ColorScheme in [.light, .dark] {
            let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
            try assertNightAnalysisMarksRemainReadable(theme, scheme: scheme)
            try assertNightControlFallbacksKeepReadableTextAndRoles(theme, scheme: scheme)
            let board = theme.board(for: scheme)
            for stone in [board.black, board.white] {
                let casing = try XCTUnwrap(stone.detailedMarkerCasing)
                XCTAssertGreaterThanOrEqual(contrast(stone.lastMove, casing, style: style), 3,
                                           "Last-move rings remain visible across glass reflections")
                XCTAssertGreaterThanOrEqual(contrast(stone.label, casing, style: style), 4.5,
                                           "Variation labels retain a contrasting casing over glass")
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
            XCTAssertGreaterThanOrEqual(contrast(board.emptyPointMarker, board.boardColor, style: style), 4.5)
        }
    }

    func testChristmasKeepsakesGlassPreservesAuthoredColorsAndFootprints() throws {
        let bundle = Bundle(for: Self.self)
        let sourceImages: [UIImage] = try ["ChristmasKeepsakesRubyStone", "ChristmasKeepsakesIvoryStone"].map { name -> UIImage in
            try XCTUnwrap(UIImage(named: name, in: bundle, compatibleWith: nil), name)
        }
        let sourcePixels = try sourceImages.map { image -> [UInt8] in
            let source = try XCTUnwrap(image.cgImage)
            return try rgbaPixels(for: source, side: source.width)
        }
        let day = try XCTUnwrap(SurroundTheme.christmasKeepsakes.board(for: .light).stoneImages)
        try assertEqualAlphaStoneFootprints(day)

        for scheme: ColorScheme in [.light, .dark, .light, .dark] {
            let board = SurroundTheme.christmasKeepsakes.board(for: scheme)
            let images = try XCTUnwrap(board.stoneImages)
            XCTAssertEqual(board.imageStoneShading, .artwork,
                           "The authored window reflection must not acquire a second contour")
            XCTAssertEqual(images.smallStoneInset, 0.45, "Keep the accepted phone packing")
            XCTAssertEqual(images.footprint, day.footprint)
            XCTAssertEqual(images.black.count, 1)
            XCTAssertEqual(images.white.count, 1)
            for (index, color) in [StoneColor.black, .white].enumerated() {
                let image = try XCTUnwrap(images.variants(color).first)
                let source = try XCTUnwrap(sourceImages[index].cgImage)
                let rendered = try XCTUnwrap(image.cgImage)
                XCTAssertEqual(rendered.width, source.width)
                XCTAssertEqual(rendered.height, source.height)
                XCTAssertEqual(image.scale, sourceImages[index].scale)
                XCTAssertEqual(image.imageOrientation, sourceImages[index].imageOrientation)
                XCTAssertEqual(try rgbaPixels(for: rendered, side: source.width), sourcePixels[index],
                               "Keep both glass colors' authored color and alpha without a second grading pass")
                XCTAssertTrue(image === (try XCTUnwrap(day.variants(color).first)),
                              "Appearance changes and clock ticks reuse the authored glass")
            }
        }
    }

    @MainActor
    func testChristmasKeepsakesPhoneStoneSpacingPreservesCentersAndCompactBoards() throws {
        for scheme: ColorScheme in [.light, .dark] {
            let images = try XCTUnwrap(SurroundTheme.christmasKeepsakes.board(for: scheme).stoneImages)
            for cell: CGFloat in [7, 13.99, 14, 14.001, 15, 16, 17, 20, 24, 31.999, 32, 40, 64] {
                let padding: CGFloat = cell < 10 ? 0 : 1
                let nominal = CGRect(x: cell * 3 + padding, y: cell * 4 + padding,
                                     width: cell - padding * 2, height: cell - padding * 2)
                let visible = images.displayRect(in: nominal, cellSize: cell)
                XCTAssertEqual(visible.midX, nominal.midX, accuracy: 0.000001)
                XCTAssertEqual(visible.midY, nominal.midY, accuracy: 0.000001)
                XCTAssertEqual(visible.width, visible.height, accuracy: 0.000001)
                XCTAssertTrue(nominal.contains(visible))
                if cell <= 14 || cell >= 32 {
                    XCTAssertEqual(visible, nominal, "Compact and large stones retain their existing size")
                } else {
                    XCTAssertLessThan(visible.width, nominal.width)
                    XCTAssertLessThan(nominal.width - visible.width, 1,
                                      "Both colors need breathing room without looking undersized")
                }
                if cell == 14.001 || cell == 31.999 {
                    XCTAssertLessThan(nominal.width - visible.width, 0.001,
                                      "Crossing either taper endpoint must not jump the silhouette")
                }
            }
            let first = images.displayRect(in: CGRect(x: 1, y: 1, width: 18, height: 18), cellSize: 20)
            let next = images.displayRect(in: CGRect(x: 21, y: 1, width: 18, height: 18), cellSize: 20)
            XCTAssertGreaterThanOrEqual(next.minX - first.maxX, 2.8,
                                        "Phone groups need a visible strip of board between adjacent stones")
            XCTAssertLessThan(next.minX - first.maxX, 3)
            XCTAssertEqual(next.midX - first.midX, 20, accuracy: 0.000001,
                           "Spacing does not move intersections or marker centers")
        }
    }

    func testIvoryContactPreservesOtherStoneShadows() {
        let ivory = ImageStoneShadowStyle.raisedIvoryGlass
        let glass = ImageStoneShadowStyle.raisedGlass
        let originalStyles: [ImageStoneShadowStyle] = [.contact, .raised, .ice, .raisedGlass]
        XCTAssertEqual(BoardAppearance.standard.imageStoneShadow, .contact)
        for scheme: ColorScheme in [.light, .dark] {
            for theme in SurroundTheme.allCases {
                XCTAssertEqual(theme.board(for: scheme).imageStoneShadow == ivory,
                               theme == .christmasKeepsakes || theme == .reefLight,
                               "The stronger contact grounds cream glass and nacre on their boards")
            }
        }
        XCTAssertTrue(ivory.usesRaisedGlassProfile)
        XCTAssertTrue(glass.usesRaisedGlassProfile)
        for cell: CGFloat in [14, 14.001, 17, 19, 20, 24, 31.999, 32, 40, 64] {
            let black = ivory.contactOpacity(for: .black, cellSize: cell)
            let white = ivory.contactOpacity(for: .white, cellSize: cell)
            XCTAssertEqual(black, glass.contactOpacity(for: .black, cellSize: cell),
                           "Dark stones retain their original contact at every detailed size")
            XCTAssertGreaterThan(white, black, "Ivory gains contact separation without changing the cast")
            XCTAssertLessThan(white, 1, "The contact must remain translucent")
            for style in originalStyles {
                XCTAssertEqual(style.contactOpacity(for: .black, cellSize: cell),
                               style.contactOpacity(for: .white, cellSize: cell),
                               "Existing shadow profiles keep the same treatment for both colors")
            }
        }
        for style in originalStyles + [ivory] {
            for cell: CGFloat in [-1, 0, 7, 13, 13.999, .infinity, .nan] {
                for color: StoneColor in [.black, .white] {
                    XCTAssertEqual(style.contactOpacity(for: color, cellSize: cell), 0,
                                   "Compact and invalid cells cannot acquire image contact shadows")
                }
            }
        }
        for endpoint: CGFloat in [22, 32] {
            for color: StoneColor in [.black, .white] {
                XCTAssertEqual(ivory.contactOpacity(for: color, cellSize: endpoint - 0.001),
                               ivory.contactOpacity(for: color, cellSize: endpoint + 0.001), accuracy: 0.0001,
                               "The phone-to-large transition must not pop while a board resizes")
            }
        }
        XCTAssertEqual(ivory.contactOpacity(for: .white, cellSize: 32),
                       ivory.contactOpacity(for: .white, cellSize: 64),
                       "Large boards cap the contact instead of increasing it with the decorations")
    }

    @MainActor
    func testCranberryGlassAccentPreservesFacesSilhouettesAndFlatStones() throws {
        for scheme: ColorScheme in [.light, .dark] {
            let board = SurroundTheme.christmasKeepsakes.board(for: scheme)
            let images = try XCTUnwrap(board.stoneImages)
            for scale: CGFloat in [2, 3] {
                for color: StoneColor in [.black, .white] {
                    for (diameter, shadow): (CGFloat, CGFloat) in [
                        (7, 1), (13.99, 1), (14, 1), (17, 1), (20, 0),
                        (20, 1), (24, 1), (40, 1), (64, 1)
                    ] {
                        func render(_ shading: ImageStoneShading) throws -> (pixels: [UInt8], width: Int, height: Int) {
                            var appearance = board
                            appearance.imageStoneShading = shading
                            return try nativeMaterialPixels(Stone(color: color, shadowRadius: shadow)
                                .frame(width: diameter, height: diameter).padding(4)
                                .environment(\.boardAppearance, appearance)
                                .environment(\.colorScheme, scheme), scale: scale)
                        }
                        // The cabochon selects its authored artwork alone;
                        // retain coverage for the optional contour renderer.
                        let actual = try render(.cranberryGlassEdge), plain = try render(.artwork)
                        let detail = "\(scheme), \(color), \(diameter) pt, \(scale)×, shadow \(shadow)"
                        XCTAssertEqual(actual.width, plain.width, detail)
                        XCTAssertEqual(actual.height, plain.height, detail)
                        if color == .white || diameter < 14 || shadow == 0 {
                            XCTAssertEqual(actual.pixels, plain.pixels,
                                           "Ivory, compact and shadowless stones remain unchanged: \(detail)")
                            continue
                        }

                        let visible = images.displayRect(in: CGRect(x: 0, y: 0, width: diameter, height: diameter),
                                                         cellSize: diameter)
                        let radius = Double(visible.width * scale) / 2
                        let centerX = Double(actual.width) / 2, centerY = Double(actual.height) / 2
                        var changedPixels = 0, brightenedPixels = 0
                        var maximumCenterDelta = 0, maximumExteriorDelta = 0, maximumAlphaDelta = 0
                        for y in 0..<actual.height {
                            for x in 0..<actual.width {
                                let offset = (y * actual.width + x) * 4
                                let distance = hypot(Double(x) + 0.5 - centerX, Double(y) + 0.5 - centerY)
                                let differences = (0..<4).map { Int(actual.pixels[offset + $0]) - Int(plain.pixels[offset + $0]) }
                                let delta = differences.map(abs).max() ?? 0
                                if delta > 1 { changedPixels += 1 }
                                if differences.prefix(3).reduce(0, +) > 3 { brightenedPixels += 1 }
                                if distance < radius * 0.65 { maximumCenterDelta = max(maximumCenterDelta, delta) }
                                // Ignore only the antialiased boundary; the
                                // accent must not extend the cast shadow.
                                if distance > radius + 2 { maximumExteriorDelta = max(maximumExteriorDelta, delta) }
                                if abs(distance - radius) > 2 {
                                    maximumAlphaDelta = max(maximumAlphaDelta, abs(differences[3]))
                                }
                            }
                        }
                        XCTAssertGreaterThan(changedPixels, 10,
                                             "The shoulder must remain visible on phone and large stones: \(detail)")
                        XCTAssertGreaterThan(brightenedPixels, 10,
                                             "Separation comes from reflected light, not a darker connecting shadow: \(detail)")
                        XCTAssertLessThanOrEqual(maximumCenterDelta, 1,
                                                 "Preserve the glass face beneath game marks: \(detail)")
                        XCTAssertLessThanOrEqual(maximumExteriorDelta, 1,
                                                 "Preserve the silhouette and external shadow: \(detail)")
                        XCTAssertLessThanOrEqual(maximumAlphaDelta, 1,
                                                 "Preserve opacity away from the antialiased edge: \(detail)")
                    }
                }
            }
        }
    }

    @MainActor
    func testChristmasKeepsakesWindowLightPreservesRenderedBoardsAtEveryDetailSize() throws {
        let scene = CGSize(width: 440, height: 520)
        let panel = CGRect(x: 12, y: 110, width: 230, height: 200)
        let frames = [CGRect(x: 24, y: 130, width: 63, height: 63),
                      CGRect(x: 115, y: 150, width: 117, height: 117),
                      CGRect(x: 240, y: 210, width: 180, height: 180)]
        for scheme: ColorScheme in [.light, .dark] {
            let appearance = SurroundTheme.christmasKeepsakes.board(for: scheme)
            func render(light: Bool, lightAboveBoards: Bool = false, untinted: Bool = false) throws
                -> (pixels: [UInt8], width: Int, height: Int) {
                var material = appearance
                if untinted { material.stoneImages?.tint = .white }
                return try nativeMaterialPixels(ZStack(alignment: .topLeading) {
                    Color(red: 0.48, green: 0.48, blue: 0.48)
                    if light && !lightAboveBoards {
                        ChristmasKeepsakesWindowLight(size: scene, scheme: scheme)
                    }
                    // Opaque panels sample the room field below their content.
                    Rectangle().fill(SurroundTheme.christmasKeepsakes.panel)
                        .overlay {
                            ChristmasKeepsakesSurfaceBeam(size: scene, origin: panel.origin,
                                                          scheme: scheme, profile: .panel)
                                .opacity(light ? 1 : 0)
                        }
                        .frame(width: panel.width, height: panel.height)
                        .clipped()
                        .offset(x: panel.minX, y: panel.minY)
                    ForEach(frames.indices, id: \.self) { index in
                        // The standalone unit target includes Stone and the
                        // opaque board pigment, but not BoardView. Both panel
                        // miniatures and the room's main board occlude light.
                        ZStack {
                            appearance.surfaceColor(detailed: false)
                            HStack(spacing: 2) {
                                Stone(color: .black, shadowRadius: 1)
                                Stone(color: .white, shadowRadius: 1)
                            }
                            .frame(width: frames[index].width * 2 / 9 + 2,
                                   height: frames[index].width / 9)
                        }
                            .frame(width: frames[index].width, height: frames[index].height)
                            .offset(x: frames[index].minX, y: frames[index].minY)
                    }
                    if light && lightAboveBoards {
                        // Wrong-layer control proves the field reaches each
                        // slab, so preservation cannot pass vacuously.
                        ChristmasKeepsakesWindowLight(size: scene, scheme: scheme)
                    }
                }
                .frame(width: scene.width, height: scene.height)
                .environment(\.surroundTheme, .christmasKeepsakes)
                .environment(\.boardAppearance, material)
                .environment(\.colorScheme, scheme)
                .environment(\.displayScale, 3))
            }
            let baseline = try render(light: false)
            let lit = try render(light: true)
            let unprotected = try render(light: true, lightAboveBoards: true)
            XCTAssertEqual(lit.width, baseline.width)
            XCTAssertEqual(lit.height, baseline.height)
            let slabs = frames.map { (rect: $0, radius: CGFloat.zero) }
            let stoneShoulders = frames.map { frame -> (centers: [CGPoint], radius: CGFloat) in
                let cell = frame.width / 9
                guard usesDetailedStoneRendering(at: cell), let images = appearance.stoneImages else {
                    return ([], 0)
                }
                let radius = images.displayRect(in: CGRect(x: 0, y: 0, width: cell, height: cell),
                                                cellSize: cell).width / 2
                // Match the centered HStack's two cells and its 2 pt spacing.
                return ([CGPoint(x: frame.midX - (cell + 2) / 2, y: frame.midY),
                         CGPoint(x: frame.midX + (cell + 2) / 2, y: frame.midY)], radius)
            }
            var changedInside = [Int](repeating: 0, count: frames.count)
            var unprotectedChanges = changedInside
            var checkedInside = changedInside
            var unexpectedChanges = changedInside
            var shoulderPixels = changedInside
            var roundedShoulderPixels = changedInside
            var roundedShoulderErrorUnits = changedInside
            var maximumChannelDelta = changedInside
            let maximumShoulderRGBDelta = 2
            var changedSamples: [[Int]] = []
            var changedOutside = 0
            for y in 0..<lit.height {
                for x in 0..<lit.width {
                    let offset = (y * lit.width + x) * 4
                    let point = CGPoint(x: (CGFloat(x) + 0.5) / 3, y: (CGFloat(y) + 0.5) / 3)
                    let differs = (0..<4).contains { lit.pixels[offset + $0] != baseline.pixels[offset + $0] }
                    var inSlab = false
                    for (index, slab) in slabs.enumerated() {
                        let qx = abs(point.x - slab.rect.midX) - (slab.rect.width / 2 - slab.radius)
                        let qy = abs(point.y - slab.rect.midY) - (slab.rect.height / 2 - slab.radius)
                        let distance = hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - slab.radius
                        if distance < -1.0 / 3 {
                            inSlab = true
                            checkedInside[index] += 1
                            let shoulder = stoneShoulders[index]
                            let isShoulder = shoulder.centers.contains { center in
                                let radius = hypot(point.x - center.x, point.y - center.y)
                                return radius >= shoulder.radius * 0.8 && radius <= shoulder.radius
                            }
                            if isShoulder { shoulderPixels[index] += 1 }
                            if differs {
                                changedInside[index] += 1
                                var pixelDelta = 0
                                for channel in 0..<4 {
                                    pixelDelta = max(pixelDelta,
                                        abs(Int(lit.pixels[offset + channel]) - Int(baseline.pixels[offset + channel])))
                                }
                                maximumChannelDelta[index] = max(maximumChannelDelta[index], pixelDelta)
                                if isShoulder, pixelDelta <= maximumShoulderRGBDelta,
                                   lit.pixels[offset + 3] == baseline.pixels[offset + 3] {
                                    roundedShoulderPixels[index] += 1
                                    roundedShoulderErrorUnits[index] += pixelDelta
                                } else {
                                    unexpectedChanges[index] += 1
                                }
                                if changedSamples.count < 40 { changedSamples.append([index, x, y]) }
                            }
                            if (0..<4).contains(where: {
                                abs(Int(unprotected.pixels[offset + $0]) - Int(baseline.pixels[offset + $0])) > maximumShoulderRGBDelta
                            }) {
                                unprotectedChanges[index] += 1
                            }
                        }
                    }
                    if !inSlab && differs { changedOutside += 1 }
                }
            }
            // iOS 26.5 can round sparse tinted-image shoulder pixels by up to
            // two RGB byte levels when the filtered room field is present.
            // Allow this only in the outer 20% of the detailed stone radius.
            // Weight each pixel by its largest RGB error to preserve the
            // original total budget: <= 0.005 error units per shoulder pixel.
            // Pigment, stone centers, compact stones and all alpha stay exact.
            let roundingErrorFractions = frames.indices.map {
                Double(roundedShoulderErrorUnits[$0]) / Double(max(1, shoulderPixels[$0]))
            }
            let needsUntintedControl = changedInside.contains { $0 > 0 }
            var untintedChangedInside = [Int](repeating: 0, count: frames.count)
            var untintedMaximumChannelDelta = untintedChangedInside
            if needsUntintedControl {
                // Any use of the rounding allowance requires exact untinted
                // slab pixels, separating tint compositing from light leakage.
                let untintedBaseline = try render(light: false, untinted: true)
                let untintedLit = try render(light: true, untinted: true)
                for (index, frame) in frames.enumerated() {
                    for y in (Int(frame.minY * 3) + 1)..<(Int(frame.maxY * 3) - 1) {
                        for x in (Int(frame.minX * 3) + 1)..<(Int(frame.maxX * 3) - 1) {
                            let offset = (y * untintedLit.width + x) * 4
                            var delta = 0
                            for channel in 0..<4 {
                                delta = max(delta, abs(Int(untintedLit.pixels[offset + channel])
                                    - Int(untintedBaseline.pixels[offset + channel])))
                            }
                            if delta > 0 { untintedChangedInside[index] += 1 }
                            untintedMaximumChannelDelta[index] = max(untintedMaximumChannelDelta[index], delta)
                        }
                    }
                }
            }
            if frames.indices.contains(where: {
                unexpectedChanges[$0] > 0 || roundingErrorFractions[$0] > 0.005 || untintedChangedInside[$0] > 0
            }) {
                let repeated = try render(light: false)
                let samples: [[String: Any]] = changedSamples.map { sample in
                    let offset = (sample[2] * baseline.width + sample[1]) * 4
                    return ["slab": sample[0], "xy": Array(sample[1...2]),
                            "baseline_rgba": Array(baseline.pixels[offset..<(offset + 4)]),
                            "lit_rgba": Array(lit.pixels[offset..<(offset + 4)]),
                            "repeated_baseline_rgba": Array(repeated.pixels[offset..<(offset + 4)])]
                }
                let diagnostic: [String: Any] = [
                    "appearance": String(describing: scheme),
                    "changed_inside": changedInside, "maximum_channel_delta": maximumChannelDelta,
                    "unexpected_changes": unexpectedChanges, "shoulder_pixels": shoulderPixels,
                    "rounded_shoulder_pixels": roundedShoulderPixels,
                    "rounded_shoulder_error_units": roundedShoulderErrorUnits,
                    "repeated_baseline_identical": repeated.pixels == baseline.pixels,
                    "untinted_control_rendered": needsUntintedControl,
                    "untinted_changed_inside": untintedChangedInside,
                    "untinted_maximum_channel_delta": untintedMaximumChannelDelta,
                    "samples": samples
                ]
                let data = try JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys])
                let text = try XCTUnwrap(String(data: data, encoding: .utf8))
                let attachment = XCTAttachment(string: text)
                attachment.name = "board-light-occlusion-\(scheme).json"
                attachment.lifetime = .keepAlways
                add(attachment)
                print("BOARD_LIGHT_OCCLUSION_DIAGNOSTIC " + text)
            }
            for index in frames.indices {
                XCTAssertGreaterThan(checkedInside[index], 1000)
                XCTAssertEqual(unexpectedChanges[index], 0,
                               "Lighting must preserve pigment, stone centers and alpha at \(frames[index].width / 9) pt (\(scheme)); maximum channel delta: \(maximumChannelDelta[index])")
                XCTAssertLessThanOrEqual(roundingErrorFractions[index], 0.005,
                                         "Shoulder RGB rounding must stay within the weighted error budget")
                XCTAssertEqual(untintedChangedInside[index], 0,
                               "Untinted slabs must remain exact whenever tinted pixels change; maximum channel delta: \(untintedMaximumChannelDelta[index])")
                XCTAssertGreaterThan(unprotectedChanges[index], 100,
                                     "Each fixture must detect lighting above the rounding allowance, so occlusion cannot pass vacuously")
            }
            XCTAssertGreaterThan(changedOutside, 1000, "The production light remains visible over the surrounding scene")
        }
    }

    func testChristmasKeepsakesWindowLightRespectsAccessibilityDisplaySettings() throws {
        // These native environment values are read-only. Verify the policy
        // used by room and material backgrounds without inventing an override.
        XCTAssertTrue(ChristmasKeepsakesWindowLight.isVisible(contrast: .standard, reduceTransparency: false))
        for (contrast, reduced): (ColorSchemeContrast, Bool) in [(.increased, false), (.standard, true), (.increased, true)] {
            XCTAssertFalse(ChristmasKeepsakesWindowLight.isVisible(contrast: contrast, reduceTransparency: reduced),
                           "Increase Contrast and Reduce Transparency each suppress the complete decorative projection")
        }
    }

    @MainActor
    func testChristmasKeepsakesSurfaceLightSamplesOneFieldAcrossSeparateCards() throws {
        let scene = CGSize(width: 440, height: 520)
        // The upper tile crosses the right shoulder; the adjacent lower
        // tiles cross both pane edges and share a seam through its falloff.
        let tiles = [CGRect(x: 40, y: 40, width: 150, height: 140),
                     CGRect(x: 20, y: 300, width: 180, height: 150),
                     CGRect(x: 200, y: 300, width: 180, height: 150)]
        for scheme: ColorScheme in [.light, .dark] {
            for profile: ChristmasKeepsakesSurfaceLighting.Profile in [.room, .panel, .glassCard,
                                                                      .ivoryGlassCard, .pigmentCard] {
                func render(origin: CGPoint, size: CGSize) throws
                    -> (pixels: [UInt8], width: Int, height: Int) {
                    try nativeMaterialPixels(ChristmasKeepsakesSurfaceBeam(
                        size: scene, origin: origin, scheme: scheme, profile: profile)
                        .frame(width: size.width, height: size.height).clipped())
                }
                let full = try render(origin: .zero, size: scene)
                for tile in tiles {
                    let cropped = try render(origin: tile.origin, size: tile.size)
                    let startX = Int(tile.minX * 3), startY = Int(tile.minY * 3)
                    XCTAssertEqual(cropped.width, Int(tile.width * 3))
                    XCTAssertEqual(cropped.height, Int(tile.height * 3))
                    var differentPixels = 0
                    var maximumDelta = 0
                    var lowestAlpha = 255, highestAlpha = 0
                    var deltaHistogram = [Int](repeating: 0, count: 256)
                    var edgePixels = [Int](repeating: 0, count: 4)
                    var edgeErrors = edgePixels
                    var gridErrors = [Int](repeating: 0, count: 144)
                    var signedChannelDelta = [Int](repeating: 0, count: 4)
                    var maximumRGBDelta = 0, maximumAlphaDelta = 0
                    var interiorMaximumDelta = 0
                    var maximumSamples = [[Int]]()
                    for y in 0..<cropped.height {
                        for x in 0..<cropped.width {
                            let local = (y * cropped.width + x) * 4
                            let global = ((y + startY) * full.width + x + startX) * 4
                            var differs = false
                            var pixelMaximumDelta = 0
                            for channel in 0..<4 {
                                let signed = Int(cropped.pixels[local + channel]) - Int(full.pixels[global + channel])
                                let delta = abs(signed)
                                signedChannelDelta[channel] += signed
                                maximumDelta = max(maximumDelta, delta)
                                pixelMaximumDelta = max(pixelMaximumDelta, delta)
                                if channel == 3 { maximumAlphaDelta = max(maximumAlphaDelta, delta) }
                                else { maximumRGBDelta = max(maximumRGBDelta, delta) }
                                differs = differs || delta > 1
                            }
                            deltaHistogram[pixelMaximumDelta] += 1
                            let edgeDistance = min(x, y, cropped.width - 1 - x, cropped.height - 1 - y)
                            let edgeBucket = edgeDistance < 4 ? 0 : (edgeDistance < 12 ? 1 : (edgeDistance < 36 ? 2 : 3))
                            edgePixels[edgeBucket] += 1
                            if edgeBucket == 3 { interiorMaximumDelta = max(interiorMaximumDelta, pixelMaximumDelta) }
                            if differs {
                                edgeErrors[edgeBucket] += 1
                                gridErrors[min(11, y * 12 / cropped.height) * 12 + min(11, x * 12 / cropped.width)] += 1
                            }
                            if pixelMaximumDelta >= 3 && maximumSamples.count < 20 {
                                maximumSamples.append([x, y, pixelMaximumDelta])
                            }
                            if differs { differentPixels += 1 }
                            lowestAlpha = min(lowestAlpha, Int(full.pixels[global + 3]))
                            highestAlpha = max(highestAlpha, Int(full.pixels[global + 3]))
                        }
                    }
                    let pixelCount = cropped.width * cropped.height
                    let pixelsAboveTwo = deltaHistogram.dropFirst(3).reduce(0, +)
                    // Gradient contours can flip rounding along a diagonal line
                    // through a card's interior (iOS 18 rasterizes more of
                    // these), so the tighter density applies only near edges.
                    let excessiveEdgeError = zip(edgeErrors, edgePixels).dropLast().contains {
                        Double($0.0) / Double($0.1) > 0.0075
                    }
                    let excessiveBias = signedChannelDelta.contains { abs(Double($0)) / Double(pixelCount) > 0.01 }
                    if maximumDelta > 3 || Double(differentPixels) / Double(pixelCount) > 0.0125
                        || Double(pixelsAboveTwo) / Double(pixelCount) > 0.0001
                        || excessiveEdgeError || excessiveBias || highestAlpha - lowestAlpha <= 2 {
                        let diagnostic: [String: Any] = [
                            "appearance": String(describing: scheme), "profile": String(describing: profile),
                            "tile": [tile.minX, tile.minY, tile.width, tile.height],
                            "pixel_size": [cropped.width, cropped.height],
                            "maximum_delta": maximumDelta, "maximum_rgb_delta": maximumRGBDelta,
                            "maximum_alpha_delta": maximumAlphaDelta, "interior_maximum_delta": interiorMaximumDelta,
                            "pixels_above_one": differentPixels, "delta_histogram": deltaHistogram,
                            "edge_distance_buckets_px": ["0-3", "4-11", "12-35", "36+"],
                            "edge_pixels": edgePixels, "edge_errors": edgeErrors,
                            "error_grid_12x12_row_major": gridErrors,
                            "signed_channel_delta_sums_rgba": signedChannelDelta,
                            "first_maximum_samples_xy_delta": maximumSamples
                        ]
                        let data = try JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys])
                        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
                        let attachment = XCTAttachment(string: text)
                        attachment.name = "light-field-\(scheme)-\(profile)-\(Int(tile.minX))-\(Int(tile.minY)).json"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                        print("LIGHT_FIELD_DIAGNOSTIC " + text)
                    }
                    XCTAssertGreaterThan(highestAlpha - lowestAlpha, 2,
                                         "Each tile must sample a changing field, including its feathered boundary")
                    // Independently rasterized masked layers accumulate sparse
                    // RGB rounding (up to three byte steps), with matching alpha
                    // and no directional bias. Bound both magnitude and local
                    // density so a coherent edge seam still fails this check.
                    XCTAssertLessThanOrEqual(maximumDelta, 3,
                                             "A card must sample the same scene field: \(scheme), \(profile), \(tile)")
                    XCTAssertLessThanOrEqual(Double(pixelsAboveTwo) / Double(pixelCount), 0.0001,
                                             "At most 0.01% of pixels may differ by more than two byte steps")
                    XCTAssertLessThanOrEqual(Double(differentPixels) / Double(pixelCount), 0.0125,
                                             "At most 1.25% of pixels may differ by more than one byte step")
                    for (errors, count) in zip(edgeErrors, edgePixels).dropLast() {
                        XCTAssertLessThanOrEqual(Double(errors) / Double(count), 0.0075,
                                                 "Rounding cannot concentrate at a card edge: \(scheme), \(profile), \(tile)")
                    }
                    for bias in signedChannelDelta {
                        XCTAssertLessThanOrEqual(abs(Double(bias)) / Double(pixelCount), 0.01,
                                                 "The sampled field must not shift a color channel systematically")
                    }
                }
            }
        }
    }

    func testChristmasKeepsakesSelectsRoomCompositionForViewportShapeAndSize() {
        let cases: [(CGSize, ChristmasKeepsakesRoomLayout.Composition)] = [
            (CGSize(width: 390, height: 844), .compactPortrait),
            (CGSize(width: 844, height: 390), .compactLandscape),
            (CGSize(width: 834, height: 1210), .regularPortrait),
            (CGSize(width: 1210, height: 834), .regularLandscape),
            (CGSize(width: 560, height: 840), .compactPortrait),
            (CGSize(width: 561, height: 840), .regularPortrait),
            (CGSize(width: 840, height: 560), .compactLandscape),
            (CGSize(width: 840, height: 561), .regularLandscape),
            (CGSize(width: 1079, height: 600), .regularLandscape),
            (CGSize(width: 1080, height: 600), .compactLandscape),
            (CGSize(width: 1920, height: 900), .compactLandscape),
            (CGSize(width: 600, height: 900), .regularPortrait),
            (CGSize(width: 440, height: 440), .compactPortrait),
            (CGSize(width: 834, height: 834), .regularPortrait)
        ]
        for (size, expected) in cases {
            XCTAssertEqual(ChristmasKeepsakesRoomLayout(size: size).composition, expected, "\(size)")
        }
    }

    func testChristmasKeepsakesRoomCoversViewportWithoutDistortionOrInvalidGeometry() {
        let sizes = [
            CGSize(width: 320, height: 568), CGSize(width: 440, height: 956),
            CGSize(width: 956, height: 440), CGSize(width: 375, height: 548),
            CGSize(width: 560, height: 840), CGSize(width: 561, height: 840),
            CGSize(width: 600, height: 900), CGSize(width: 834, height: 1210),
            CGSize(width: 1210, height: 834), CGSize(width: 1920, height: 1080),
            CGSize(width: 1920, height: 900), CGSize(width: 1600, height: 700),
            CGSize(width: 1080, height: 2400),
            CGSize(width: 100, height: 140), .zero, CGSize(width: -20, height: 40),
            CGSize(width: CGFloat.infinity, height: CGFloat.nan)
        ]
        for size in sizes {
            let layout = ChristmasKeepsakesRoomLayout(size: size)
            for frame in [layout.backdrop, layout.lightingReference] {
                XCTAssertTrue(frame.minX.isFinite && frame.minY.isFinite, "\(size)")
                XCTAssertTrue(frame.width.isFinite && frame.height.isFinite, "\(size)")
                XCTAssertGreaterThanOrEqual(frame.width, 0)
                XCTAssertGreaterThanOrEqual(frame.height, 0)
                XCTAssertEqual(frame.width, frame.height, accuracy: 0.001,
                               "Room pixels and the lighting reference must retain their square proportions")
            }
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { continue }
            let viewport = CGRect(origin: .zero, size: size)
            XCTAssertTrue(layout.backdrop.contains(viewport), "\(size): no uncovered strip at any edge")
            XCTAssertEqual(layout.backdrop.minX, 0, accuracy: 0.001)
            XCTAssertEqual(layout.backdrop.maxY, size.height, accuracy: 0.001,
                           "The whole room composition stays anchored to the bottom-leading viewport corner")
        }
    }

    func testChristmasKeepsakesPhoneLandscapeRevealsFrostAtUnchangedScale() {
        for size in [CGSize(width: 667, height: 375), CGSize(width: 844, height: 390),
                     CGSize(width: 874, height: 402), CGSize(width: 956, height: 440)] {
            let original = ChristmasKeepsakesRoomLayout(size: size)
            let phone = ChristmasKeepsakesRoomLayout(size: size, usesPhoneLandscapeFraming: true)
            XCTAssertEqual(phone.composition, .compactLandscape)
            XCTAssertEqual(phone.backdrop.size, original.backdrop.size,
                           "More frost must not enlarge the room or its gifts")
            XCTAssertEqual(phone.backdrop.minX, original.backdrop.minX)
            XCTAssertGreaterThan(phone.backdrop.minY, original.backdrop.minY)
            XCTAssertTrue(phone.backdrop.contains(CGRect(origin: .zero, size: size)),
                          "Reframing must leave no uncovered viewport edge")
            // The useful frost lies immediately above the original bottom
            // 44% crop. Retain source pixels from at least its 52% height.
            let croppedTopFraction = max(0, -phone.backdrop.minY) / phone.backdrop.height
            XCTAssertLessThanOrEqual(croppedTopFraction, 0.52,
                                    "Ordinary phone landscape must show glass above the sill")
            let bottomCrop = phone.backdrop.maxY - size.height
            XCTAssertGreaterThan(bottomCrop, 0)
            XCTAssertLessThanOrEqual(bottomCrop, size.height * 0.13,
                                     "Gift bases may crop modestly while their bodies remain in the scene")
            XCTAssertEqual(phone.lightingReference, original.lightingReference)
            XCTAssertEqual(phone.lightCenter, original.lightCenter,
                           "Reframing the photograph must not move lighting on the UI")
        }
        for size in [CGSize(width: 100, height: 1), .zero, CGSize(width: -20, height: 40),
                     CGSize(width: CGFloat.infinity, height: CGFloat.nan)] {
            let frame = ChristmasKeepsakesRoomLayout(size: size, usesPhoneLandscapeFraming: true).backdrop
            XCTAssertTrue(frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite)
            if size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 {
                XCTAssertTrue(frame.contains(CGRect(origin: .zero, size: size)))
            }
        }
    }

    func testChristmasKeepsakesPhoneFramingPreservesOtherRoomContexts() {
        // The caller opts in only for an undivided phone. Duo, iPad, Home
        // and picker contexts retain the default bottom-anchored profile.
        for size in [CGSize(width: 678, height: 466), CGSize(width: 840, height: 560),
                     CGSize(width: 1210, height: 834), CGSize(width: 1920, height: 900),
                     CGSize(width: 440, height: 440), CGSize(width: 874, height: 402)] {
            let original = ChristmasKeepsakesRoomLayout(size: size)
            let unchanged = ChristmasKeepsakesRoomLayout(size: size, usesPhoneLandscapeFraming: false)
            XCTAssertEqual(unchanged, original)
            XCTAssertEqual(unchanged.backdrop.maxY, size.height, accuracy: 0.001)
        }
        // The phone profile may remain enabled through rotation; the layout
        // itself limits it to the compact landscape photograph.
        for size in [CGSize(width: 375, height: 667), CGSize(width: 402, height: 874),
                     CGSize(width: 440, height: 956), CGSize(width: 440, height: 440),
                     CGSize(width: 1210, height: 834), CGSize(width: 678, height: 466),
                     CGSize(width: 600, height: 440), CGSize(width: 660, height: 440)] {
            XCTAssertEqual(ChristmasKeepsakesRoomLayout(size: size, usesPhoneLandscapeFraming: true),
                           ChristmasKeepsakesRoomLayout(size: size),
                           "Portrait and narrow landscapes, including Closed Duo without a visible division, retain their crop")
        }
        func bottomCrop(aspect: CGFloat) -> CGFloat {
            let size = CGSize(width: 400 * aspect, height: 400)
            return ChristmasKeepsakesRoomLayout(size: size, usesPhoneLandscapeFraming: true).backdrop.maxY - size.height
        }
        XCTAssertEqual(bottomCrop(aspect: 1.5), 0, accuracy: 0.000001)
        XCTAssertGreaterThan(bottomCrop(aspect: 1.625), 0)
        XCTAssertLessThan(bottomCrop(aspect: 1.625), bottomCrop(aspect: 1.75))
        XCTAssertEqual(bottomCrop(aspect: 1.75), bottomCrop(aspect: 2), accuracy: 0.000001)
        for boundary: CGFloat in [1.5, 1.75] {
            XCTAssertEqual(bottomCrop(aspect: boundary - 0.00001), bottomCrop(aspect: boundary + 0.00001),
                           accuracy: 0.01, "The reveal must ease continuously while a viewport resizes")
        }
    }

    func testChristmasKeepsakesRoomRetainsWindowAreaInShortAndWideViewports() {
        // Each composition places its window at a different height in the
        // source plate. Bound the discarded top portion independently of
        // the sizing formula so short windows cannot crop it down to the sill.
        let cases: [(CGSize, CGFloat)] = [
            (CGSize(width: 320, height: 568), 0.05),
            (CGSize(width: 375, height: 548), 0.05),
            (CGSize(width: 600, height: 900), 0.17),
            (CGSize(width: 1920, height: 900), 0.57),
            (CGSize(width: 1600, height: 700), 0.57)
        ]
        for (size, maximumTopCrop) in cases {
            let layout = ChristmasKeepsakesRoomLayout(size: size)
            let croppedTopFraction = max(0, -layout.backdrop.minY) / layout.backdrop.height
            XCTAssertLessThanOrEqual(croppedTopFraction, maximumTopCrop,
                                    "\(size): retain the window region of the selected composition")
        }
    }

    func testChristmasKeepsakesRoomRevealsMoreTableAtStableScaleWithinEachComposition() {
        let pairs: [(CGSize, CGSize)] = [
            (CGSize(width: 440, height: 956), CGSize(width: 440, height: 1000)),
            (CGSize(width: 956, height: 440), CGSize(width: 1000, height: 440)),
            (CGSize(width: 834, height: 1210), CGSize(width: 834, height: 1376)),
            (CGSize(width: 1210, height: 834), CGSize(width: 1376, height: 834))
        ]
        for (smallerSize, largerSize) in pairs {
            let smaller = ChristmasKeepsakesRoomLayout(size: smallerSize)
            let larger = ChristmasKeepsakesRoomLayout(size: largerSize)
            XCTAssertEqual(smaller.composition, larger.composition)
            XCTAssertEqual(smaller.backdrop.size, larger.backdrop.size,
                           "More viewport space reveals the composition without enlarging its gifts and needles")
            XCTAssertGreaterThan(largerSize.width * largerSize.height,
                                 smallerSize.width * smallerSize.height)
            XCTAssertEqual(smaller.backdrop.maxY, smallerSize.height, accuracy: 0.001)
            XCTAssertEqual(larger.backdrop.maxY, largerSize.height, accuracy: 0.001)
        }
        let smallPhone = ChristmasKeepsakesRoomLayout(size: CGSize(width: 320, height: 568))
        let largePhone = ChristmasKeepsakesRoomLayout(size: CGSize(width: 440, height: 956))
        XCTAssertLessThan(smallPhone.backdrop.width, largePhone.backdrop.width,
                          "The smallest phones need a proportionate composition, not an oversized crop")
    }

    func testChristmasKeepsakesTreeKeepsBoundedAspectAndViewportEdge() {
        let artworkSize = CGSize(width: 768, height: 1536)
        let sizes = [
            CGSize(width: 375, height: 667), CGSize(width: 667, height: 375),
            CGSize(width: 402, height: 874), CGSize(width: 874, height: 402),
            CGSize(width: 440, height: 956), CGSize(width: 956, height: 440),
            CGSize(width: 466, height: 678), CGSize(width: 678, height: 466),
            CGSize(width: 669, height: 951), CGSize(width: 951, height: 669),
            CGSize(width: 834, height: 1210), CGSize(width: 1210, height: 834),
            CGSize(width: 1032, height: 1376), CGSize(width: 1376, height: 1032),
            CGSize(width: 1920, height: 1080)
        ]
        for size in sizes {
            let frame = ChristmasKeepsakesTreeLayout(size: size, artworkSize: artworkSize).frame
            let visible = frame.intersection(CGRect(origin: .zero, size: size))
            XCTAssertEqual(frame.width / frame.height, artworkSize.width / artworkSize.height, accuracy: 0.000001,
                           "Upright branches and hanging ornaments must not stretch")
            XCTAssertGreaterThan(frame.maxX, size.width, "The trunk continues beyond the right edge")
            XCTAssertGreaterThan(frame.maxY, size.height, "The lower cut edge stays outside the viewport")
            XCTAssertGreaterThan(visible.width, 20)
            XCTAssertLessThanOrEqual(visible.width, 80, "Only a narrow tree edge should enter the room")
            XCTAssertGreaterThanOrEqual(frame.minX, size.width * 0.8)
            XCTAssertGreaterThan(visible.height, 0)
            XCTAssertLessThanOrEqual(frame.height, 600, "Tablets must not inflate the tree")
            let rotated = ChristmasKeepsakesTreeLayout(size: CGSize(width: size.height, height: size.width),
                                                       artworkSize: artworkSize).frame
            XCTAssertEqual(rotated.size, frame.size, "Rotation changes the crop, not the material scale")
        }
        let tablet = ChristmasKeepsakesTreeLayout(size: CGSize(width: 834, height: 1210), artworkSize: artworkSize)
        let largerTablet = ChristmasKeepsakesTreeLayout(size: CGSize(width: 1032, height: 1376), artworkSize: artworkSize)
        XCTAssertEqual(tablet.frame.size, largerTablet.frame.size)
        let preview = ChristmasKeepsakesTreeLayout(size: CGSize(width: 100, height: 140), artworkSize: artworkSize)
        XCTAssertLessThan(preview.frame.height, 140, "Preview tiles need proportionate artwork")
        for size in [CGSize.zero, CGSize(width: -20, height: 40),
                     CGSize(width: CGFloat.infinity, height: CGFloat.nan)] {
            XCTAssertEqual(ChristmasKeepsakesTreeLayout(size: size, artworkSize: artworkSize).frame, .zero)
        }
        for invalidArtwork in [CGSize.zero, CGSize(width: 1, height: -1),
                               CGSize(width: CGFloat.infinity, height: 1),
                               CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.leastNonzeroMagnitude)] {
            XCTAssertEqual(ChristmasKeepsakesTreeLayout(size: CGSize(width: 402, height: 874),
                                                       artworkSize: invalidArtwork).frame, .zero)
        }
    }

    func testChristmasKeepsakesChangesLightingWithoutMovingTheBoard() throws {
        let theme = SurroundTheme.christmasKeepsakes
        let day = theme.board(for: .light), night = theme.board(for: .dark)
        XCTAssertEqual(theme.board, day)
        XCTAssertLessThan(luminance(night.boardColor), luminance(day.boardColor))
        XCTAssertLessThan(luminance(try XCTUnwrap(night.compactBoardColor)),
                          luminance(try XCTUnwrap(day.compactBoardColor)))
        XCTAssertEqual(day.gridStyle, .straight)
        XCTAssertEqual(night.gridStyle, day.gridStyle)
        XCTAssertEqual(night.gridLineScale, day.gridLineScale)
        XCTAssertEqual(night.stoneLightDirection, day.stoneLightDirection)
        let dayDepth = try XCTUnwrap(day.boardDepth)
        let nightDepth = try XCTUnwrap(night.boardDepth)
        XCTAssertEqual(nightDepth.thicknessRatio, dayDepth.thicknessRatio)
        XCTAssertEqual(nightDepth.maximumThickness, dayDepth.maximumThickness)
        for board in [day, night] {
            XCTAssertEqual(board.boardDepth?.edgeStyle, .rolledTin)
            XCTAssertTrue(board.boardBevel)
        }
        for size in [CGSize(width: 260, height: 260), CGSize(width: 330, height: 330),
                     CGSize(width: 440, height: 440), CGSize(width: 834, height: 834)] {
            for coordinates in [false, true] {
                for scale: CGFloat in [2, 3] {
                    let dayLayout = BoardDepthGeometry(containerSize: size, boardWidth: 19, boardHeight: 19,
                        showsCoordinates: coordinates, displayScale: scale, depth: dayDepth)
                    let nightLayout = BoardDepthGeometry(containerSize: size, boardWidth: 19, boardHeight: 19,
                        showsCoordinates: coordinates, displayScale: scale, depth: nightDepth)
                    XCTAssertEqual(dayLayout, nightLayout,
                                   "Appearance changes light and material pigments, never the board's inset or hit geometry")
                }
            }
        }
        // Asset integrity uses the test bundle below. The cached main-bundle
        // image wrappers may be nil in this unhosted unit target.
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

    @MainActor
    func testKoiPondPebbleChipsCarryMineralGrainBehindReadableNames() throws {
        let theme = SurroundTheme.koiPond
        for scheme: ColorScheme in [.light, .dark] {
            let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
            for stone: StoneColor in [.black, .white] {
                let inks = [theme.identityForeground(stone), theme.identitySecondary(stone),
                            theme.clockForeground(stone, scheme: scheme), theme.clockAccent(stone),
                            theme.clockSuddenDeathAccent(stone, scheme: scheme),
                            theme.roleColor(for: OGSUser(username: "moderator", id: 1, isModerator: true), on: stone),
                            theme.roleColor(for: OGSUser(username: "supporter", id: 2, supporter: true), on: stone)]
                for size in [CGSize(width: 150, height: 54), CGSize(width: 86, height: 36)] {
                    let chip = KoiPondPebbleChip(color: stone, cornerRadius: 11)
                        .frame(width: size.width, height: size.height)
                        .environment(\.colorScheme, scheme)
                    let image = try nativeMaterialPixels(chip, scale: 1)
                    var grain = 0, low = 255, high = 0
                    var darkest = Color.white, lightest = Color.black
                    for y in 7..<(image.height - 7) {
                        for x in 7..<(image.width - 7) {
                            let i = (y * image.width + x) * 4
                            // A smooth gradient has negligible curvature across adjacent
                            // pixels. Real mineral grit survives inside the rim at both sizes.
                            let center = Int(image.pixels[i])
                            if abs(2 * center - Int(image.pixels[i - 4]) - Int(image.pixels[i + 4])) >= 3 {
                                grain += 1
                            }
                            if center < low || center > high {
                                XCTAssertEqual(image.pixels[i + 3], 255)
                                let pigment = Color(red: Double(center) / 255,
                                                    green: Double(image.pixels[i + 1]) / 255,
                                                    blue: Double(image.pixels[i + 2]) / 255)
                                if center < low { low = center; darkest = pigment }
                                if center > high { high = center; lightest = pigment }
                            }
                        }
                    }
                    let sample = "\(scheme) \(stone) \(size)"
                    XCTAssertGreaterThan(grain, 12, "The player chip retains the stone's grain: \(sample)")
                    for ink in inks {
                        XCTAssertGreaterThanOrEqual(contrast(ink, darkest, style: style), 4.5, sample)
                        XCTAssertGreaterThanOrEqual(contrast(ink, lightest, style: style), 4.5, sample)
                    }
                }
            }
        }
    }

    @MainActor
    func testKoiPondBambooLedgeKeepsItsShapeAndChangesFinishAtBothSizes() throws {
        for compact in [false, true] {
            let width: CGFloat = compact ? 179 : 208
            func render(_ running: Bool) throws -> (pixels: [UInt8], width: Int, height: Int) {
                try nativeMaterialPixelsUsingDirectContext(
                    KoiPondBambooLedge(compact: compact, running: running).frame(width: width), scale: 3)
            }
            let honey = try render(true), smoke = try render(false)
            XCTAssertEqual(honey.width, Int(width) * 3)
            XCTAssertEqual(honey.height, 18, "The ledge fits the existing six-point clearance")
            XCTAssertEqual(honey.width, smoke.width)
            XCTAssertEqual(honey.height, smoke.height)
            let alpha = stride(from: 3, to: honey.pixels.count, by: 4)
            XCTAssertTrue(alpha.allSatisfy { honey.pixels[$0] == smoke.pixels[$0] },
                          "Changing the turn preserves the outline, nodes and shadow")
            let midX = honey.width / 2
            let body = (0..<honey.height).filter { honey.pixels[($0 * honey.width + midX) * 4 + 3] > 240 }
            XCTAssertTrue((compact ? 11...14 : 14...17).contains(body.count),
                          "The visible cane keeps its full or compact diameter")
            let midY = try XCTUnwrap(body.dropFirst(body.count / 2).first)
            let row = (0..<honey.width).filter { honey.pixels[(midY * honey.width + $0) * 4 + 3] > 240 }
            let inset = compact ? 18 : 24
            XCTAssertEqual(try XCTUnwrap(row.first), inset, accuracy: 2)
            XCTAssertEqual(try XCTUnwrap(row.last), honey.width - inset - 1, accuracy: 2)
            let center = (midY * honey.width + midX) * 4
            let r = Int(honey.pixels[center]), g = Int(honey.pixels[center + 1]), b = Int(honey.pixels[center + 2])
            XCTAssertGreaterThan(r - g, 15)
            XCTAssertGreaterThan(g - b, 35)
            XCTAssertGreaterThan(r - Int(smoke.pixels[center]), 75)
            XCTAssertLessThan(abs(Int(smoke.pixels[center]) - Int(smoke.pixels[center + 1])), 8)
        }
    }

    func testGoldenCrumbUsesScoredShortbreadAndReadableCookieSurfaces() throws {
        let theme = SurroundTheme.goldenCrumb
        for scheme: ColorScheme in [.light, .dark] {
            let board = theme.board(for: scheme)
            XCTAssertEqual(board.gridStyle, .shortbreadScore)
            let texture = try XCTUnwrap(board.boardTexture)
            XCTAssertEqual(texture.mapping, .framed,
                           "Rectangular games preserve all four sides of the toasted rim")
            let slab = BoardDepthGeometry(containerSize: CGSize(width: 390, height: 390),
                                         boardWidth: 19, boardHeight: 19, showsCoordinates: false,
                                         displayScale: 3, depth: board.boardDepth)
            XCTAssertGreaterThan(slab.cornerRadius, slab.thickness)
            XCTAssertLessThanOrEqual(slab.cornerRadius, slab.cellSize / 2)
            let cookies = try XCTUnwrap(board.stoneImages)
            XCTAssertEqual(cookies.black.count, 1)
            XCTAssertEqual(cookies.white.count, 1)
            XCTAssertNil(board.boardReflection)
            XCTAssertFalse(theme.allowsGlassOnPlayerSurfaces)
            try assertNightControlFallbacksKeepReadableTextAndRoles(theme, scheme: scheme)
            try assertNightAnalysisMarksRemainReadable(theme, scheme: scheme)
        }
    }

    @MainActor
    func testGoldenCrumbStampedSurfacesKeepClockAndPlayerTextReadable() throws {
        let theme = SurroundTheme.goldenCrumb
        let player = OGSUser(username: "player", id: 1)
        for stone: StoneColor in [.black, .white] {
            for scheme: ColorScheme in [.light, .dark] {
                let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
                let inks = [theme.clockForeground(stone, scheme: scheme), theme.clockAccent(stone),
                            theme.clockSuddenDeathAccent(stone, scheme: scheme),
                            theme.identitySecondary(stone), theme.roleColor(for: player, on: stone)]
                for size in [CGSize(width: 298, height: 96), CGSize(width: 140, height: 50),
                             CGSize(width: 120, height: 34)] {
                    let image = try nativeMaterialPixelsUsingDirectContext(
                        GoldenCrumbCookieSurface(color: stone, cornerRadius: 12)
                            .frame(width: size.width, height: size.height)
                            .environment(\.colorScheme, scheme), scale: 1)
                    XCTAssertEqual(image.width, Int(size.width))
                    XCTAssertEqual(image.height, Int(size.height))
                    // Sample where names, counters and footer labels sit, inside the stamped lip.
                    var lowestContrast = Double.infinity
                    var weakestPoint = CGPoint.zero
                    var reds = [UInt8]()
                    for y in stride(from: 8, to: image.height - 8, by: 3) {
                        for x in stride(from: 12, to: image.width - 12, by: 7) {
                            let i = 4 * (y * image.width + x)
                            XCTAssertEqual(image.pixels[i + 3], 255)
                            reds.append(image.pixels[i])
                            let pigment = Color(red: Double(image.pixels[i]) / 255,
                                                green: Double(image.pixels[i + 1]) / 255,
                                                blue: Double(image.pixels[i + 2]) / 255)
                            for ink in inks {
                                let ratio = contrast(ink, pigment, style: style)
                                if ratio < lowestContrast {
                                    lowestContrast = ratio
                                    weakestPoint = CGPoint(x: x, y: y)
                                }
                            }
                        }
                    }
                    let sample = "\(stone), \(scheme), \(size)"
                    XCTAssertGreaterThan(try XCTUnwrap(reds.max()) - XCTUnwrap(reds.min()), 2,
                                         "The biscuit grain is present at \(sample)")
                    XCTAssertGreaterThanOrEqual(lowestContrast, 4.5, "\(sample) at \(weakestPoint)")
                }
            }
        }
    }

    @MainActor
    func testGoldenCrumbRunningFlourMarksTheLowerEdgeAndWarningSurroundsTheClock() throws {
        let padding: CGFloat = 8
        let scale: CGFloat = 3
        for size in [CGSize(width: 298, height: 96), CGSize(width: 120, height: 34)] {
            let face = CGRect(origin: CGPoint(x: padding, y: padding), size: size)
            for stone: StoneColor in [.black, .white] {
                for scheme: ColorScheme in [.light, .dark] {
                    func render(_ flour: GoldenCrumbCookieSurface.FlourPrint?) throws -> [UInt8] {
                        try nativeMaterialPixelsUsingDirectContext(
                            GoldenCrumbCookieSurface(color: stone, cornerRadius: 12,
                                                    edgeClearance: size.height == 34 ? 4 : 6, flour: flour)
                                .frame(width: size.width, height: size.height)
                                .padding(padding)
                                .environment(\.colorScheme, scheme), scale: scale).pixels
                    }
                    let idle = try render(nil), running = try render(.running), warning = try render(.warning)
                    let width = Int((size.width + padding * 2) * scale)
                    func changedPixels(_ printPixels: [UInt8], in region: CGRect, tolerance: Int = 8) -> Int {
                        var count = 0
                        for y in Int(ceil(region.minY * scale))..<Int(floor(region.maxY * scale)) {
                            for x in Int(ceil(region.minX * scale))..<Int(floor(region.maxX * scale)) {
                                let i = (y * width + x) * 4
                                if (0..<4).contains(where: { abs(Int(printPixels[i + $0]) - Int(idle[i + $0])) > tolerance }) {
                                    count += 1
                                }
                            }
                        }
                        return count
                    }
                    // Sample the flour on the bench outside the biscuit, clear
                    // of the rounded corners. The warning can leave breaks in the print.
                    let top = CGRect(x: face.minX + size.width * 0.15, y: 0,
                                     width: size.width * 0.7, height: padding)
                    let bottom = top.offsetBy(dx: 0, dy: face.maxY)
                    let left = CGRect(x: 0, y: face.minY + size.height * 0.25,
                                      width: padding, height: size.height * 0.5)
                    let sample = "\(stone), \(scheme), \(size)"
                    XCTAssertGreaterThan(changedPixels(running, in: bottom), 16, sample)
                    XCTAssertEqual(changedPixels(running, in: top), 0, sample)
                    for edge in [top, bottom, left, left.offsetBy(dx: face.maxX, dy: 0)] {
                        XCTAssertGreaterThan(changedPixels(warning, in: edge), 4, "\(sample), edge \(edge)")
                    }
                    let text = face.insetBy(dx: 8, dy: 8)
                    for printed in [running, warning] {
                        XCTAssertEqual(changedPixels(printed, in: text, tolerance: 1), 0,
                                       "Flour preserves every pixel beneath the live labels at \(sample)")
                    }
                }
            }
        }
    }

    func testGoldenCrumbCrustContinuesTheToastedRimAndDarkensAtItsFoot() throws {
        let texture = try XCTUnwrap(SurroundTheme.goldenCrumb.board(for: .light).boardTexture)
        let face = try XCTUnwrap(texture.image.cgImage)
        let wall = try XCTUnwrap(texture.frontSurface?.cgImage)
        XCTAssertEqual(wall.width, face.width)
        func pigment(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
            let patch = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 8, height: 1)))
            return try rgbaPixels(for: patch, side: 1)
        }
        for x in [face.width / 8, face.width / 2, face.width * 7 / 8] {
            let rim = try pigment(face, x: x, y: face.height - 1)
            let lip = try pigment(wall, x: x, y: 0)
            let foot = try pigment(wall, x: x, y: wall.height - 1)
            for channel in 0..<3 {
                XCTAssertEqual(Double(lip[channel]), Double(rim[channel]), accuracy: 12,
                               "The wall begins at the local rim color without a bright seam")
                XCTAssertLessThan(foot[channel], lip[channel], "The wall shades toward the table")
            }
        }
    }

    @MainActor
    func testGoldenCrumbWorkbenchKeepsCornerArtAndReadableLegacyChrome() throws {
        let theme = SurroundTheme.goldenCrumb
        let wood = try XCTUnwrap(UIImage(named: "GoldenCrumbWalnutBench", in: GoldenCrumb.bundle, compatibleWith: nil))
        XCTAssertNotNil(UIImage(named: "GoldenCrumbLinenCorner", in: GoldenCrumb.bundle, compatibleWith: nil))
        for size in [CGSize(width: 360, height: 700), CGSize(width: 840, height: 390)] {
            let plain = try nativeMaterialPixelsUsingDirectContext(Image(uiImage: wood)
                .resizable().scaledToFill().frame(width: size.width, height: size.height).clipped(), scale: 1)
            for scheme: ColorScheme in [.light, .dark] {
                let scene = try nativeMaterialPixelsUsingDirectContext(GameDetailBackdrop()
                    .environment(\.surroundTheme, theme).environment(\.colorScheme, scheme)
                    .frame(width: size.width, height: size.height), scale: 1)
                // Both viewport shapes leave a patch of bare bench at the board center.
                let centerX = scene.width / 2, centerY = scene.height / 2
                var totalRed = 0, woodRed = 0, mismatched = 0
                for y in (centerY - 12)..<(centerY + 12) {
                    for x in (centerX - 12)..<(centerX + 12) {
                        let i = (y * scene.width + x) * 4
                        totalRed += Int(scene.pixels[i])
                        woodRed += Int(plain.pixels[i])
                        if (0..<3).contains(where: { abs(Int(scene.pixels[i + $0]) - Int(plain.pixels[i + $0])) > 4 }) {
                            mismatched += 1
                        }
                    }
                }
                if scheme == .dark {
                    XCTAssertLessThan(Double(totalRed), Double(woodRed) * 0.8, "Dim the walnut in Dark Mode")
                    XCTAssertGreaterThan(Double(totalRed), Double(woodRed) * 0.25, "Retain the warm wood in Dark Mode")
                } else {
                    XCTAssertLessThan(mismatched, 24, "The middle of the playing area shows uninterrupted walnut")
                }
                if #available(iOS 26, macCatalyst 26, *) {
                    guard scheme == .light else { continue }
                    // Native glass leaves the linen, pastry, cocoa and cutter visible.
                    // Compare their own regions with the identical bare-wood crop.
                    let edge = min(scene.width, scene.height) / 3
                    for x0 in [0, scene.width - edge] {
                        for y0 in [0, scene.height - edge] {
                            var changed = 0
                            for y in y0..<(y0 + edge) {
                                for x in x0..<(x0 + edge) {
                                    let i = (y * scene.width + x) * 4
                                    if abs(Int(scene.pixels[i]) - Int(plain.pixels[i])) > 18 { changed += 1 }
                                }
                            }
                            XCTAssertGreaterThan(changed, edge * edge / 50,
                                                 "Visible corner artwork at (\(x0), \(y0)) in \(size)")
                        }
                    }
                    // The linen and its shadow occupy about 52 × 64 pt on a
                    // 360 pt phone. The space below and to its right stays bare
                    // through the middle of the compact clock row.
                    let shortSide = min(scene.width, scene.height)
                    let hemWidth = Int(ceil(Double(shortSide) * 0.15))
                    let hemHeight = Int(ceil(Double(shortSide) * 0.19))
                    var coveredWood = 0
                    for y in stride(from: 1, to: edge, by: 2) {
                        for x in stride(from: 1, to: centerX, by: 2) where x >= hemWidth || y >= hemHeight {
                            let i = (y * scene.width + x) * 4
                            if (0..<3).contains(where: { abs(Int(scene.pixels[i + $0]) - Int(plain.pixels[i + $0])) > 8 }) {
                                coveredWood += 1
                            }
                        }
                    }
                    XCTAssertLessThanOrEqual(coveredWood, 2, "Leave clear walnut between the linen and the clocks in \(size)")
                } else {
                    // Older navigation and toolbar labels sit on the scene's edge gradients.
                    let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
                    for y in [26, scene.height - 26] {
                        for x in stride(from: centerX - 50, through: centerX + 50, by: 10) {
                            let i = (y * scene.width + x) * 4
                            let backing = Color(red: Double(scene.pixels[i]) / 255,
                                                green: Double(scene.pixels[i + 1]) / 255,
                                                blue: Double(scene.pixels[i + 2]) / 255)
                            XCTAssertGreaterThanOrEqual(contrast(theme.foreground, backing, style: style), 4.5,
                                                       "Unglazed toolbar text at (\(x), \(y)) in \(size), \(scheme)")
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testGoldenCrumbScoreHasTwoVisibleWallsOnRectangularBoards() throws {
        let columns = 6, rows = 9
        let scale: CGFloat = 3
        for scheme: ColorScheme in [.light, .dark] {
            let board = SurroundTheme.goldenCrumb.board(for: scheme)
            let depth = try XCTUnwrap(board.boardDepth)
            for cell: CGFloat in [7, 13, 20, 38] {
                let grid = EngravedGridGeometry(width: columns, height: rows, cellSize: cell,
                                                lineScale: board.gridLineScale)
                let field = board.boardColor.frame(width: CGFloat(columns) * cell, height: CGFloat(rows) * cell)
                let plain = try nativeMaterialPixelsUsingDirectContext(field, scale: scale)
                let scored = try nativeMaterialPixelsUsingDirectContext(field.overlay {
                    ShortbreadScoredGrid(geometry: grid, shade: depth.shade, highlight: depth.highlight)
                }, scale: scale)
                if cell < 14 {
                    XCTAssertTrue(scored.pixels == plain.pixels, "The compact grid must add no relief at \(cell) pt")
                    continue
                }
                func relief(at point: CGPoint) -> Int {
                    let offset = 4 * (Int(point.y * scale) * scored.width + Int(point.x * scale))
                    return (0..<3).reduce(0) { $0 + Int(scored.pixels[offset + $1]) - Int(plain.pixels[offset + $1]) } / 3
                }
                // Include the bottom and right borders: a square or transposed
                // overlay would paint the wrong number of lanes on this board.
                for horizontal in [true, false] {
                    let count = horizontal ? rows : columns
                    for line in [1, count - 2, count - 1] {
                        let axis = (CGFloat(line) + 0.5) * cell
                        for along in [2, 4] {
                            func crossSection(_ direction: CGFloat) -> [Int] {
                                (1...9).map { pixel in
                                    let across = axis + direction * CGFloat(pixel) / scale
                                    let betweenIntersections = CGFloat(along) * cell
                                    return relief(at: CGPoint(x: horizontal ? betweenIntersections : across,
                                                              y: horizontal ? across : betweenIntersections))
                                }
                            }
                            let sample = "\(scheme), \(cell) pt, \(horizontal ? "row" : "column") \(line), span \(along)"
                            XCTAssertLessThan(try XCTUnwrap(crossSection(-1).min()), -8, "The upper/left wall casts shade at \(sample)")
                            XCTAssertGreaterThan(try XCTUnwrap(crossSection(1).max()), 7, "The lower/right wall catches light at \(sample)")
                        }
                    }
                }
                XCTAssertEqual(relief(at: CGPoint(x: 3 * cell, y: 7 * cell)), 0, "The middle of a cell stays clear")
                XCTAssertEqual(relief(at: CGPoint(x: 5.9 * cell, y: 7.5 * cell)), 0, "Rows end at the right edge of the rectangular grid")
            }
        }
    }

    func testKoiPondControlSurfacesAndAnalysisMarksInBothAppearances() throws {
        for scheme: ColorScheme in [.light, .dark] {
            try assertNightControlFallbacksKeepReadableTextAndRoles(.koiPond, scheme: scheme)
            try assertNightAnalysisMarksRemainReadable(.koiPond, scheme: scheme)
        }
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
                if theme == .surroundStudio || theme == .feltMeadow || theme == .nightGarden || theme == .christmasKeepsakes || theme == .paperBlossoms || theme == .sakuraStream || theme == .whittledWoodland || theme == .reefLight || theme == .koiPond || theme == .goldenCrumb {
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
        if theme == .surroundStudio || theme == .feltMeadow || theme == .nightGarden || theme == .christmasKeepsakes || theme == .paperBlossoms || theme == .sakuraStream || theme == .whittledWoodland || theme == .reefLight || theme == .koiPond || theme == .goldenCrumb {
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
    func testFeltClockRunningStitchLeavesGapsAndProtectsTheClothEdge() throws {
        let scale: CGFloat = 2
        let padding: CGFloat = 3
        func delta(_ a: [UInt8], _ b: [UInt8], _ i: Int) -> Int {
            max(abs(Int(a[i]) - Int(b[i])), abs(Int(a[i + 1]) - Int(b[i + 1])),
                abs(Int(a[i + 2]) - Int(b[i + 2])), abs(Int(a[i + 3]) - Int(b[i + 3])))
        }
        for scheme: ColorScheme in [.light, .dark] {
            for color: StoneColor in [.black, .white] {
                for size in [CGSize(width: 140, height: 28), CGSize(width: 88, height: 34),
                             CGSize(width: 190, height: 96)] {
                    let shape = RoundedRectangle(cornerRadius: size.height == 28 ? 8 : 12)
                    let rect = CGRect(origin: CGPoint(x: padding, y: padding), size: size)
                    let outer = shape.inset(by: 0.5).path(in: rect)
                    let content = shape.inset(by: 5).path(in: rect)
                    for textured in [false, true] {
                        func render(_ warning: Bool?) throws -> (pixels: [UInt8], width: Int, height: Int) {
                            try nativeMaterialPixelsUsingDirectContext(
                                FeltControlMaterial(color: color, shape: shape, colorScheme: scheme, showsTexture: textured,
                                                    runningClock: warning != nil, isWarning: warning == true)
                                    .frame(width: size.width, height: size.height)
                                    .padding(padding)
                                    .environment(\.colorScheme, scheme), scale: scale)
                        }
                        let idle = try render(nil)
                        let running = try render(false).pixels
                        let warning = try render(true).pixels
                        let description = "\(scheme) \(color) \(size), textured=\(textured)"
                        XCTAssertTrue(stride(from: 0, to: running.count, by: 4).contains {
                            delta(running, warning, $0) > 32
                        }, "Sudden death changes the thread color: \(description)")
                        for active in [running, warning] {
                            let touchesProtectedArea = stride(from: 0, to: active.count, by: 4).contains { offset in
                                guard delta(active, idle.pixels, offset) > 3 else { return false }
                                let x = offset / 4 % idle.width, y = offset / 4 / idle.width
                                let point = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                                return !outer.contains(point) || content.contains(point)
                            }
                            XCTAssertFalse(touchesProtectedArea, "Protect the loose fibers and the clock content: \(description)")

                            // Project each straight section across the seam's thickness. A solid ring
                            // cannot pass the gap check, and a top-only treatment misses three sides.
                            for vertical in [false, true] {
                                let length = Int((vertical ? size.height : size.width) * scale)
                                let inset = Int(padding * scale), skipCorner = Int(9 * scale)
                                for farSide in [false, true] {
                                    let peaks = (skipCorner..<(length - skipCorner)).map { along in
                                        (0..<Int(5 * scale)).map { depth in
                                            let cross = farSide ? (vertical ? idle.width : idle.height) - 1 - inset - depth
                                                                : inset + depth
                                            let x = vertical ? cross : inset + along
                                            let y = vertical ? inset + along : cross
                                            return delta(active, idle.pixels, (y * idle.width + x) * 4)
                                        }.max() ?? 0
                                    }
                                    XCTAssertTrue(peaks.contains { $0 > 50 }, "Visible thread on every edge: \(description)")
                                    XCTAssertTrue(peaks.contains { $0 < 5 }, "Cloth shows between stitches: \(description)")
                                }
                            }
                        }
                    }
                }
            }
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

    @MainActor
    func testNightGardenPanesKeepActualTextReservesOpaqueAndReadable() throws {
        let theme = SurroundTheme.nightGarden
        let scale = 3
        let linear = (0...255).map { byte -> Double in
            let value = Double(byte) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let players = [OGSUser(username: "ordinary", id: 1),
                       OGSUser(username: "moderator", id: 2, isModerator: true),
                       OGSUser(username: "admin", id: 3, isSuperuser: true),
                       OGSUser(username: "professional", id: 4, professional: true),
                       OGSUser(username: "supporter", id: 5, supporter: true),
                       OGSUser(username: "bot", id: 6, isBot: true)]
        // Actual caller reserves, including the tight Home and header chips.
        // Enlarging the test's reserve would conceal a bevel under real text.
        let cases: [(name: String, role: NightGardenPaneRole, size: CGSize,
                     inset: CGSize, compact: Bool)] = [
            ("Home clock", .clock, CGSize(width: 140, height: 28), CGSize(width: 9, height: 5), true),
            ("inline clock", .clock, CGSize(width: 320, height: 34), CGSize(width: 8, height: 6), true),
            ("compact clock", .clock, CGSize(width: 160, height: 52), CGSize(width: 8, height: 4), true),
            ("full clock", .clock, CGSize(width: 190, height: 96), CGSize(width: 12, height: 4), false),
            ("narrow clock", .clock, CGSize(width: 104, height: 144), CGSize(width: 10, height: 8), true),
            ("wide clock", .clock, CGSize(width: 420, height: 96), CGSize(width: 12, height: 4), false),
            ("large clock", .clock, CGSize(width: 680, height: 144), CGSize(width: 12, height: 4), false),
            ("row player", .player, CGSize(width: 156, height: 52), CGSize(width: 4, height: 8), false),
            ("short row player", .player, CGSize(width: 108, height: 52), CGSize(width: 4, height: 8), false),
            ("compact column player", .player, CGSize(width: 126, height: 84), CGSize(width: 5, height: 5), true),
            ("full vertical player", .player, CGSize(width: 156, height: 144), CGSize(width: 8, height: 8), true),
            ("header player", .player, CGSize(width: 220, height: 44), CGSize(width: 4, height: 8), true)
        ]
        for scheme: ColorScheme in [.light, .dark] {
            let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
            for color: StoneColor in [.black, .white] {
                let playerSolid = try XCTUnwrap(theme.identityChipColors(color).first)
                let identityInks: [(String, Color)] = [
                    ("identity", theme.identityForeground(color)), ("secondary", theme.identitySecondary(color))
                ] + players.map { ($0.username, theme.roleColor(for: $0, on: color)) }
                let clockInks: [(String, Color)] = [
                    ("clock", theme.clockForeground(color, scheme: scheme)),
                    ("accent", theme.clockAccent(color)),
                    ("sudden death", theme.clockSuddenDeathAccent(color, scheme: scheme)),
                    ("agreement", theme.clockAgreementAccent(color, scheme: scheme)),
                    ("disconnected", theme.clockDisconnectedAccent(color, scheme: scheme)),
                    ("undo", theme.clockUndoAccent(color, scheme: scheme)),
                    ("Home active", theme.homeChipAccent(color))
                ] + identityInks
                for sample in cases {
                    let solid = sample.role == .player ? playerSolid : theme.clockSolidSurface(color)
                    let plain = try nativeMaterialPixels(NightGardenPaneOutline(compact: sample.compact).fill(solid)
                        .frame(width: sample.size.width, height: sample.size.height)
                        .environment(\.colorScheme, scheme))
                    for detailed in [false, true] {
                        let actual = try nativeMaterialPixels(NightGardenPaneMaterial(color: color, role: sample.role,
                            colorScheme: scheme, showsDetail: detailed, compact: sample.compact)
                            .frame(width: sample.size.width, height: sample.size.height)
                            .environment(\.colorScheme, scheme))
                        let message = "\(sample.name), \(scheme), \(color), detailed=\(detailed)"
                        XCTAssertEqual(actual.width, Int(sample.size.width) * scale, message)
                        XCTAssertEqual(actual.height, Int(sample.size.height) * scale, message)
                        let reserve = CGRect(origin: .zero, size: sample.size)
                            .insetBy(dx: sample.inset.width, dy: sample.inset.height)
                        var minimum = Double.infinity, maximum = -Double.infinity
                        var minimumPoint = CGPoint.zero, maximumPoint = CGPoint.zero
                        var minimumAlpha: UInt8 = 255
                        for y in Int(reserve.minY) * scale..<Int(reserve.maxY) * scale {
                            for x in Int(reserve.minX) * scale..<Int(reserve.maxX) * scale {
                                let offset = (y * actual.width + x) * 4
                                minimumAlpha = min(minimumAlpha, actual.pixels[offset + 3])
                                let value = 0.2126 * linear[Int(actual.pixels[offset])]
                                    + 0.7152 * linear[Int(actual.pixels[offset + 1])]
                                    + 0.0722 * linear[Int(actual.pixels[offset + 2])]
                                if value < minimum {
                                    minimum = value
                                    minimumPoint = CGPoint(x: x, y: y)
                                }
                                if value > maximum {
                                    maximum = value
                                    maximumPoint = CGPoint(x: x, y: y)
                                }
                            }
                        }
                        XCTAssertEqual(minimumAlpha, 255, "Every actual text-reserve pixel stays opaque: \(message)")
                        for (name, ink) in sample.role == .player ? identityInks : clockInks {
                            let value = luminance(ink, style: style)
                            let nearest = min(maximum, max(minimum, value))
                            let ratio = (max(value, nearest) + 0.05) / (min(value, nearest) + 0.05)
                            let worst = value >= maximum ? maximumPoint : minimumPoint
                            XCTAssertGreaterThanOrEqual(ratio, 4.5,
                                "\(name) ratio=\(ratio), inkL=\(value), materialL=\(minimum)...\(maximum), "
                                + "minXY=\(minimumPoint), maxXY=\(maximumPoint), nearestXY=\(worst) at native3x; \(message)")
                        }
                        if !detailed {
                            XCTAssertEqual(actual.pixels, plain.pixels,
                                "Fallback is exactly the role's solid outline without glass or relief: \(message)")
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testNightGardenPanesKeepSolidFallbackAndStayInsideControlBounds() throws {
        let scale = 3, padding = 8
        let cases: [(role: NightGardenPaneRole, size: CGSize, compact: Bool)] = [
            (.clock, CGSize(width: 140, height: 28), true),
            (.clock, CGSize(width: 190, height: 96), false),
            (.clock, CGSize(width: 104, height: 144), true),
            (.player, CGSize(width: 156, height: 52), false),
            (.player, CGSize(width: 126, height: 84), true),
            (.player, CGSize(width: 220, height: 44), true)
        ]
        for scheme: ColorScheme in [.light, .dark] {
            for color: StoneColor in [.black, .white] {
                for sample in cases {
                    func material(_ detailed: Bool) throws -> (pixels: [UInt8], width: Int, height: Int) {
                        try nativeMaterialPixels(NightGardenPaneMaterial(color: color, role: sample.role,
                            colorScheme: scheme, showsDetail: detailed, compact: sample.compact)
                            .frame(width: sample.size.width, height: sample.size.height)
                            .padding(CGFloat(padding)).environment(\.colorScheme, scheme))
                    }
                    let detailed = try material(true), fallback = try material(false)
                    let message = "\(scheme), \(color), \(sample.role), \(sample.size), compact=\(sample.compact)"
                    var exteriorAlpha: UInt8 = 0, changedEdge = 0, edgeCount = 0
                    for y in 0..<detailed.height {
                        for x in 0..<detailed.width {
                            let offset = (y * detailed.width + x) * 4
                            let localX = CGFloat(x) / CGFloat(scale) - CGFloat(padding)
                            let localY = CGFloat(y) / CGFloat(scale) - CGFloat(padding)
                            if localX < 0 || localY < 0 || localX >= sample.size.width || localY >= sample.size.height {
                                exteriorAlpha = max(exteriorAlpha, detailed.pixels[offset + 3], fallback.pixels[offset + 3])
                            } else if localX > 12 && localX < sample.size.width - 12
                                        && (localY < 3 || localY > sample.size.height - 3) {
                                edgeCount += 1
                                let delta = (0..<3).map { abs(Int(detailed.pixels[offset + $0]) - Int(fallback.pixels[offset + $0])) }.max()!
                                if delta >= 8 { changedEdge += 1 }
                            }
                        }
                    }
                    XCTAssertEqual(exteriorAlpha, 0, "Panes never invade adjacent content or hit targets: \(message)")
                    XCTAssertGreaterThan(Double(changedEdge) / Double(edgeCount), 0.2,
                        "The native glass shoulder must visibly differ from a flat card: \(message)")
                    // These accessibility values are read-only platform
                    // environments. The explicit fallback is verified above;
                    // this render checks the ordinary wrapper's appearance
                    // forwarding without inventing a test-only environment.
                    let surface = try nativeMaterialPixels(NightGardenPaneSurface(color: color, role: sample.role,
                        compact: sample.compact)
                        .frame(width: sample.size.width, height: sample.size.height).padding(CGFloat(padding))
                        .environment(\.colorScheme, scheme))
                    XCTAssertEqual(surface.pixels, detailed.pixels,
                        "The ordinary production wrapper forwards the selected appearance and material: \(message)")
                }
            }
        }
    }

    @MainActor
    func testNightGardenClockHighlightsStandOutAlongTheGlassEdges() throws {
        let scale: CGFloat = 3
        for (size, compact) in [(CGSize(width: 140, height: 28), true),
                                (CGSize(width: 190, height: 96), false)] {
            let bounds = CGRect(origin: .zero, size: size)
            let face = NightGardenPaneOutline(compact: compact).inset(by: 4).path(in: bounds)
            let width = Int(size.width * scale)
            for scheme: ColorScheme in [.light, .dark] {
                for color: StoneColor in [.white, .black] {
                    for detailed in [true, false] {
                        func render(_ highlight: NightGardenClockHighlight?) throws -> [UInt8] {
                            try nativeMaterialPixelsUsingDirectContext(
                                NightGardenPaneMaterial(color: color, role: .clock, colorScheme: scheme,
                                    showsDetail: detailed, compact: compact, highlight: highlight)
                                    .frame(width: size.width, height: size.height)
                                    .environment(\.colorScheme, scheme), scale: scale).pixels
                        }
                        let idle = try render(nil)
                        let running = try render(.running)
                        let warning = try render(.warning)
                        let detail = "\(color), \(scheme), \(size), detailed=\(detailed)"
                        XCTAssertTrue(running != warning, "The warning changes the turn cue: \(detail)")
                        for active in [running, warning] {
                            let changed = stride(from: 0, to: idle.count, by: 4).filter { i in
                                (0..<4).contains { abs(Int(active[i + $0]) - Int(idle[i + $0])) > 8 }
                            }
                            XCTAssertTrue(changed.allSatisfy { i in
                                let point = CGPoint(x: (CGFloat(i / 4 % width) + 0.5) / scale,
                                                    y: (CGFloat(i / 4 / width) + 0.5) / scale)
                                let outsideCentralFacets = !detailed || abs(point.x - bounds.midX) > size.width / 4
                                return idle[i + 3] > 0 && !face.contains(point) && outsideCentralFacets
                            }, "The cue stays on the chamfer and leaves the text and facets inside it clear: \(detail)")

                            // Read the actual glass just inside each side and compare it with the
                            // strongest part of the lit edge. The satin shoulder varies with size.
                            for fromRight in [false, true] {
                                func sample(_ pixels: [UInt8], inset: Int) -> Color {
                                    let x = fromRight ? width - 1 - inset : inset
                                    let i = (Int(size.height * scale / 2) * width + x) * 4
                                    return Color(.sRGB, red: Double(pixels[i]) / 255,
                                                 green: Double(pixels[i + 1]) / 255, blue: Double(pixels[i + 2]) / 255)
                                }
                                let glass = sample(idle, inset: Int(6 * scale))
                                let edge = (0..<Int(4 * scale)).compactMap { inset -> Double? in
                                    let ink = sample(active, inset: inset)
                                    return ink == sample(idle, inset: inset) ? nil : contrast(ink, glass)
                                }
                                XCTAssertGreaterThanOrEqual(edge.max() ?? 0, 3, "Visible turn on either pane: \(detail)")
                            }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testNightGardenPaneTexturesCacheTheSameArtworkAtBothMaterialScales() throws {
        var fields = [Data]()
        for color: StoneColor in [.black, .white] {
            let regular = try XCTUnwrap(NightGardenPaneTexture.image(color: color))
            let compact = try XCTUnwrap(NightGardenPaneTexture.image(color: color, compact: true))
            XCTAssertTrue(regular === NightGardenPaneTexture.image(color: color), "Clock ticks reuse decoded regular glass")
            XCTAssertTrue(compact === NightGardenPaneTexture.image(color: color, compact: true), "Compact chips reuse decoded glass")
            let source = try XCTUnwrap(regular.cgImage)
            XCTAssertTrue(source === compact.cgImage, "Changing role/size does not repaint or resample the source artwork")
            XCTAssertGreaterThan(source.width, 256)
            XCTAssertGreaterThan(source.width, source.height, "Panes are wide source fields, not stretched stone art")
            for (image, isCompact) in [(regular, false), (compact, true)] {
                XCTAssertEqual(image.scale, isCompact ? 8 : 4)
                let caps = NightGardenPaneTexture.capInsets(compact: isCompact)
                XCTAssertGreaterThan(caps.leading, 0)
                XCTAssertGreaterThan(caps.top, 0)
                XCTAssertEqual(caps.leading, caps.trailing)
                XCTAssertEqual(caps.top, caps.bottom)
                XCTAssertLessThan(caps.leading + caps.trailing, image.size.width,
                                  "Keep a nonempty quiet center to stretch between the source shoulders")
                XCTAssertLessThan(caps.top + caps.bottom, image.size.height)
            }
            fields.append(Data(try rgbaPixels(for: source, side: 256)))
        }
        XCTAssertNotEqual(fields[0], fields[1], "Amethyst and champagne retain distinct photographed material")
    }

    func testNightGardenPaneOutlinesKeepFiniteNestedGeometry() {
        for compact in [false, true] {
            let shape = NightGardenPaneOutline(compact: compact)
            for size in [CGSize(width: 1, height: 1), CGSize(width: 12, height: 12),
                         CGSize(width: 140, height: 28), CGSize(width: 104, height: 144),
                         CGSize(width: 680, height: 144)] {
                let rect = CGRect(origin: CGPoint(x: 17, y: 23), size: size)
                let path = shape.path(in: rect)
                XCTAssertFalse(path.isEmpty)
                XCTAssertEqual(path.boundingRect, rect, "The pane keeps its caller's exact geometry")
                for amount: CGFloat in [0.25, 0.5, 2, 5] where amount * 2 < min(size.width, size.height) {
                    let inset = shape.inset(by: amount).path(in: rect)
                    XCTAssertFalse(inset.isEmpty)
                    XCTAssertTrue(rect.contains(inset.boundingRect))
                    XCTAssertEqual(inset.boundingRect.minX, rect.minX + amount, accuracy: 0.001)
                    XCTAssertEqual(inset.boundingRect.minY, rect.minY + amount, accuracy: 0.001)
                    XCTAssertEqual(inset.boundingRect.maxX, rect.maxX - amount, accuracy: 0.001)
                    XCTAssertEqual(inset.boundingRect.maxY, rect.maxY - amount, accuracy: 0.001)
                    XCTAssertTrue(inset.contains(CGPoint(x: rect.midX, y: rect.midY)))
                }
            }
            for rect in [CGRect.zero, CGRect.null, CGRect.infinite,
                         CGRect(x: 0, y: 0, width: CGFloat.nan, height: 20),
                         CGRect(x: 0, y: 0, width: 20, height: 0)] {
                XCTAssertTrue(shape.path(in: rect).isEmpty, "Invalid/transitional layout slots draw no path")
            }
            XCTAssertTrue(shape.inset(by: 20).path(in: CGRect(x: 0, y: 0, width: 12, height: 12)).isEmpty)
        }
    }

    @MainActor
    func testChristmasKeepsakeRunningClockPinstripeFollowsThePaintedFace() throws {
        let theme = SurroundTheme.christmasKeepsakes
        let scale: CGFloat = 3
        for scheme: ColorScheme in [.light, .dark] {
            for side: StoneColor in [.black, .white] {
                for (size, compact) in [(CGSize(width: 140, height: 28), true),
                                        (CGSize(width: 190, height: 96), false)] {
                    func render<Outline: View>(@ViewBuilder outline: () -> Outline) throws
                        -> (pixels: [UInt8], width: Int, height: Int) {
                        try nativeMaterialPixelsUsingDirectContext(
                            ChristmasOrnamentMaterial(color: side, role: .clock, colorScheme: scheme,
                                                      showsDetail: true, compact: compact)
                                .overlay(content: outline)
                                .frame(width: size.width, height: size.height)
                                .environment(\.surroundTheme, theme)
                                .environment(\.colorScheme, scheme), scale: scale)
                    }
                    let detail = "\(scheme), \(side), \(size)"
                    let wood = try render { EmptyView() }
                    let idle = try render { GameDetailMatteClockOutline(color: side, isRunning: false) }
                    XCTAssertTrue(idle.pixels == wood.pixels, "Idle leaves the painted wood bare: \(detail)")

                    let sample = (Int(4 * scale) * wood.width + wood.width / 2) * 4
                    func inkAtSample(_ pixels: [UInt8]) -> Color {
                        Color(.sRGB, red: Double(pixels[sample]) / 255, green: Double(pixels[sample + 1]) / 255,
                              blue: Double(pixels[sample + 2]) / 255)
                    }
                    var runningInks: [Color] = []
                    for warning in [false, true] {
                        let ink = warning ? theme.clockSuddenDeathAccent(side, scheme: scheme) : theme.clockAccent(side)
                        let expected = try render {
                            // The exposed wood ends at 2.4 pt. Check the whole contour,
                            // including the diagonal cuts and the painted strip outside the ink.
                            ChristmasOrnamentOutline(role: .clock).inset(by: 3)
                                .strokeBorder(ink, lineWidth: 2)
                        }
                        let actual = try render {
                            GameDetailMatteClockOutline(color: side, isRunning: true, isWarning: warning)
                        }
                        XCTAssertTrue(actual.pixels == expected.pixels, "Painted pinstripe: \(detail), warning=\(warning)")
                        let renderedInk = inkAtSample(actual.pixels)
                        XCTAssertGreaterThanOrEqual(contrast(renderedInk, inkAtSample(wood.pixels)), 3, detail)
                        runningInks.append(renderedInk)
                    }
                    XCTAssertNotEqual(runningInks[0], runningInks[1], "Low time changes the ink: \(detail)")
                }
            }
        }
    }

    @MainActor
    func testChristmasKeepsakeOrnamentTextRegionsStayOpaqueAndReadable() throws {
        let theme = SurroundTheme.christmasKeepsakes
        let scale = 3
        let linear = (0...255).map { byte -> Double in
            let value = Double(byte) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let players = [OGSUser(username: "ordinary", id: 1),
                       OGSUser(username: "moderator", id: 2, isModerator: true),
                       OGSUser(username: "admin", id: 3, isSuperuser: true),
                       OGSUser(username: "professional", id: 4, professional: true),
                       OGSUser(username: "supporter", id: 5, supporter: true),
                       OGSUser(username: "bot", id: 6, isBot: true)]
        // Explicit roles and actual caller reserves: the same wood material
        // must protect each layout independently. Full/compact clocks keep
        // 12/8 pt horizontal and 4 pt vertical padding. A normal identity has
        // 4 pt outside a 44 pt row, with its name
        // stack centered vertically; compact columns have 5 pt and full vertical
        // columns have 8 pt. Header controls use the compact depth profile.
        let cases: [(name: String, role: ChristmasOrnamentRole, size: CGSize,
                     inset: CGSize, compact: Bool)] = [
            ("Home clock", .clock, CGSize(width: 140, height: 28), CGSize(width: 9, height: 5), true),
            ("inline clock", .clock, CGSize(width: 320, height: 34), CGSize(width: 8, height: 6), true),
            ("compact clock", .clock, CGSize(width: 160, height: 52), CGSize(width: 8, height: 4), false),
            ("full clock", .clock, CGSize(width: 190, height: 96), CGSize(width: 12, height: 4), false),
            ("narrow clock", .clock, CGSize(width: 104, height: 144), CGSize(width: 10, height: 8), true),
            ("wide clock", .clock, CGSize(width: 420, height: 96), CGSize(width: 12, height: 4), false),
            ("large clock", .clock, CGSize(width: 680, height: 144), CGSize(width: 12, height: 4), false),
            ("row player", .player, CGSize(width: 156, height: 52), CGSize(width: 4, height: 8), false),
            ("short row player", .player, CGSize(width: 108, height: 52), CGSize(width: 4, height: 8), false),
            ("compact column player", .player, CGSize(width: 126, height: 84), CGSize(width: 5, height: 5), true),
            ("full vertical player", .player, CGSize(width: 156, height: 144), CGSize(width: 8, height: 8), true),
            ("wide vertical player", .player, CGSize(width: 240, height: 160), CGSize(width: 8, height: 8), true),
            // The header's 32 pt avatar and single name/rank line are vertically
            // centered in the 44 pt hit target; its depth stays inside the bounds.
            ("header player", .player, CGSize(width: 220, height: 44), CGSize(width: 4, height: 8), true)
        ]
        for scheme: ColorScheme in [.light, .dark] {
            let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
            for color: StoneColor in [.black, .white] {
                let playerSolid = try XCTUnwrap(theme.identityChipColors(color).first)
                let identityInks: [(String, Color)] = [
                    ("identity", theme.identityForeground(color)),
                    ("secondary", theme.identitySecondary(color))
                ] + players.map { ($0.username, theme.roleColor(for: $0, on: color)) }
                let clockInks: [(String, Color)] = [
                    ("clock", theme.clockForeground(color, scheme: scheme)),
                    ("accent", theme.clockAccent(color)),
                    ("sudden death", theme.clockSuddenDeathAccent(color, scheme: scheme)),
                    ("agreement", theme.clockAgreementAccent(color, scheme: scheme)),
                    ("disconnected", theme.clockDisconnectedAccent(color, scheme: scheme)),
                    ("undo", theme.clockUndoAccent(color, scheme: scheme)),
                    ("Home active", theme.homeChipAccent(color))
                ] + identityInks
                for sample in cases {
                    let solid = sample.role == .player ? playerSolid : theme.clockSolidSurface(color)
                    let plain = try nativeMaterialPixels(ChristmasOrnamentOutline(role: sample.role).fill(solid)
                        .frame(width: sample.size.width, height: sample.size.height)
                        .environment(\.colorScheme, scheme))
                    for detailed in [false, true] {
                        let material = ChristmasOrnamentMaterial(color: color, role: sample.role,
                            colorScheme: scheme, showsDetail: detailed, compact: sample.compact)
                        let actual = try nativeMaterialPixels(material
                            .frame(width: sample.size.width, height: sample.size.height)
                            .environment(\.colorScheme, scheme))
                        let message = "\(sample.name), \(scheme), \(color), detailed=\(detailed)"
                        XCTAssertEqual(actual.width, Int(sample.size.width) * scale, message)
                        XCTAssertEqual(actual.height, Int(sample.size.height) * scale, message)
                        let textRect = CGRect(origin: .zero, size: sample.size)
                            .insetBy(dx: sample.inset.width, dy: sample.inset.height)
                        var minimum = Double.infinity, maximum = 0.0
                        var minimumAlpha: UInt8 = 255
                        var fallbackDifference = 0
                        for y in Int(textRect.minY) * scale..<Int(textRect.maxY) * scale {
                            for x in Int(textRect.minX) * scale..<Int(textRect.maxX) * scale {
                                let offset = (y * actual.width + x) * 4
                                minimumAlpha = min(minimumAlpha, actual.pixels[offset + 3])
                                let value = 0.2126 * linear[Int(actual.pixels[offset])]
                                    + 0.7152 * linear[Int(actual.pixels[offset + 1])]
                                    + 0.0722 * linear[Int(actual.pixels[offset + 2])]
                                minimum = min(minimum, value)
                                maximum = max(maximum, value)
                                if !detailed {
                                    for channel in 0..<4 {
                                        fallbackDifference = max(fallbackDifference,
                                            abs(Int(actual.pixels[offset + channel]) - Int(plain.pixels[offset + channel])))
                                    }
                                }
                            }
                        }
                        XCTAssertEqual(minimumAlpha, 255, "The caller's entire text reserve stays opaque: \(message)")
                        for (name, ink) in sample.role == .player ? identityInks : clockInks {
                            let value = luminance(ink, style: style)
                            let nearest = min(maximum, max(minimum, value))
                            XCTAssertGreaterThanOrEqual((max(value, nearest) + 0.05)
                                / (min(value, nearest) + 0.05), 4.5,
                                "\(name) must read over every native material tone in the actual text reserve: \(message)")
                        }
                        if !detailed {
                            XCTAssertEqual(actual.pixels, plain.pixels,
                                "Fallback is the exact solid outline with no bevel or grain: \(message)")
                            XCTAssertEqual(fallbackDifference, 0,
                                "Accessibility fallback uses the exact solid role-specific pigment, without relief or grain: \(message)")
                            XCTAssertLessThan(maximum - minimum, 0.001, message)
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testChristmasKeepsakeOrnamentsKeepVisibleWoodAndBoundedDepth() throws {
        let scale = 3, padding = 12
        // Caller-selected profiles, not a height heuristic. The regular clock
        // and row player may have exposed depth; constrained surfaces keep all
        // ornament detail inside their original bounds.
        let cases: [(role: ChristmasOrnamentRole, size: CGSize, compact: Bool)] = [
            (.clock, CGSize(width: 140, height: 28), true),
            (.clock, CGSize(width: 160, height: 52), false),
            (.clock, CGSize(width: 190, height: 96), false),
            (.clock, CGSize(width: 104, height: 144), true),
            (.player, CGSize(width: 156, height: 52), false),
            (.player, CGSize(width: 126, height: 84), true),
            (.player, CGSize(width: 156, height: 144), true),
            (.player, CGSize(width: 220, height: 44), true)
        ]
        for scheme: ColorScheme in [.light, .dark] {
            for color: StoneColor in [.black, .white] {
                for role in ChristmasOrnamentRole.allCases {
                    for sample in cases where sample.role == role {
                        let size = sample.size
                        func render(detailed: Bool = true) throws -> (pixels: [UInt8], width: Int, height: Int) {
                            try nativeMaterialPixels(ChristmasOrnamentMaterial(color: color, role: role,
                                colorScheme: scheme, showsDetail: detailed, compact: sample.compact)
                                .frame(width: size.width, height: size.height).padding(CGFloat(padding))
                                .environment(\.colorScheme, scheme))
                        }
                        let material = try render()
                        let message = "\(role), \(scheme), \(color), \(size), compact=\(sample.compact)"
                        func encodedLuma(_ pixels: [UInt8], _ offset: Int) -> Double {
                            0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1])
                                + 0.0722 * Double(pixels[offset + 2])
                        }

                        // The wood is a real exposed edge, not merely a change
                        // to the face pigment. Compare straight-edge pixels with
                        // the adjacent paint, avoiding corners and antialiasing.
                        var visibleEdge = 0, edgeCount = 0
                        var edgeTones: [Double] = []
                        for x in (padding + Int(size.width / 4)) * scale..<(padding + Int(size.width * 3 / 4)) * scale {
                            for top in [true, false] {
                                let edgeY = (padding + (top ? 1 : Int(size.height) - 2)) * scale
                                let faceY = (padding + (top ? 6 : Int(size.height) - 7)) * scale
                                let edgeOffset = (edgeY * material.width + x) * 4
                                let faceOffset = (faceY * material.width + x) * 4
                                let difference = (0..<3).map {
                                    abs(Int(material.pixels[edgeOffset + $0]) - Int(material.pixels[faceOffset + $0]))
                                }.max()!
                                if difference >= 8 { visibleEdge += 1 }
                                edgeCount += 1
                                edgeTones.append(encodedLuma(material.pixels, edgeOffset))
                            }
                        }
                        XCTAssertGreaterThan(Double(visibleEdge) / Double(edgeCount), 0.5,
                            "Exposed bare wood must visibly separate from the paint: \(message)")
                        let edgeMaximum = try XCTUnwrap(edgeTones.max())
                        let edgeMinimum = try XCTUnwrap(edgeTones.min())
                        XCTAssertGreaterThan(edgeMaximum - edgeMinimum, 10,
                            "The bevel must retain visible wood/light relief: \(message)")

                        // Average native pixels to logical phone points and
                        // remove a planar gradient. This checks that the paint's
                        // real grain is visible, rather than letting a smooth
                        // gradient or an almost-transparent texture pass.
                        let face = CGRect(origin: .zero, size: size).insetBy(dx: 16, dy: 8)
                        let centerX = (face.minX + face.maxX - 1) / 2
                        let centerY = (face.minY + face.maxY - 1) / 2
                        var samples: [(x: Double, y: Double, value: Double)] = []
                        for y in Int(face.minY)..<Int(face.maxY) {
                            for x in Int(face.minX)..<Int(face.maxX) {
                                var value = 0.0
                                for py in (padding + y) * scale..<(padding + y + 1) * scale {
                                    for px in (padding + x) * scale..<(padding + x + 1) * scale {
                                        value += encodedLuma(material.pixels, (py * material.width + px) * 4)
                                    }
                                }
                                samples.append((Double(CGFloat(x) - centerX), Double(CGFloat(y) - centerY),
                                                value / Double(scale * scale)))
                            }
                        }
                        let mean = samples.reduce(0) { $0 + $1.value } / Double(samples.count)
                        let slopeX = samples.reduce(0) { $0 + $1.x * ($1.value - mean) }
                            / samples.reduce(0) { $0 + $1.x * $1.x }
                        let slopeY = samples.reduce(0) { $0 + $1.y * ($1.value - mean) }
                            / samples.reduce(0) { $0 + $1.y * $1.y }
                        let residuals = samples.map { $0.value - mean - slopeX * $0.x - slopeY * $0.y }.sorted()
                        let spread = residuals[(residuals.count - 1) * 9 / 10]
                            - residuals[(residuals.count - 1) / 10]
                        let rms = sqrt(residuals.reduce(0) { $0 + $1 * $1 } / Double(residuals.count))
                        // Selected reference paint has fine, quieter brush
                        // relief than the first rough-grain candidate. This
                        // lower bound still rejects a flat/gradient-only face;
                        // it is not a requirement for coarse wood texture.
                        XCTAssertGreaterThanOrEqual(spread, 3,
                            "Broad paint/grain variation must remain visible at logical1x: \(message), spread=\(spread)")
                        XCTAssertGreaterThanOrEqual(rms, 0.8,
                            "Isolated pixels cannot substitute for painted wood texture: \(message), rms=\(rms)")

                        let fallback = try render(detailed: false)
                        var depthInk = 0
                        var exteriorAlpha: UInt8 = 0, fallbackAlpha: UInt8 = 0
                        var beyondDepthAllowanceAlpha: UInt8 = 0
                        for y in 0..<material.height {
                            for x in 0..<material.width {
                                let outsideLeft = x < padding * scale
                                let outsideRight = x >= (padding + Int(size.width)) * scale
                                let outsideVertical = y < padding * scale || y >= (padding + Int(size.height)) * scale
                                guard outsideLeft || outsideRight || outsideVertical else { continue }
                                let offset = (y * material.width + x) * 4
                                exteriorAlpha = max(exteriorAlpha, material.pixels[offset + 3])
                                fallbackAlpha = max(fallbackAlpha, fallback.pixels[offset + 3])
                                if material.pixels[offset + 3] >= 64 { depthInk += 1 }
                                // Regular plaques retain their exposed wood and
                                // contact shade inside the original 7 pt allowance.
                                if x < (padding - 7) * scale || x >= (padding + Int(size.width) + 7) * scale
                                    || y < (padding - 7) * scale || y >= (padding + Int(size.height) + 7) * scale {
                                    beyondDepthAllowanceAlpha = max(beyondDepthAllowanceAlpha, material.pixels[offset + 3])
                                }
                            }
                        }
                        XCTAssertEqual(fallbackAlpha, 0, "Solid fallback has no bevel or exterior depth: \(message)")
                        XCTAssertEqual(beyondDepthAllowanceAlpha, 0, "Wood depth stays in the bounded free envelope: \(message)")
                        if sample.compact {
                            XCTAssertEqual(exteriorAlpha, 0, "Constrained ornaments have no exterior depth: \(message)")
                        } else {
                            XCTAssertGreaterThan(depthInk, 20, "Regular ornament thickness must visibly extend beyond the paint bounds: \(message)")
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testChristmasKeepsakeOrnamentAssetsLoadOpaqueCachedTextures() throws {
        let bundle = Bundle(for: Self.self)
        var sourceFields: [Data] = []
        for name in ["ChristmasKeepsakesPaintedWood", "ChristmasKeepsakesBareWood"] {
            let source = try XCTUnwrap(UIImage(named: name, in: bundle, compatibleWith: nil)?.cgImage, name)
            XCTAssertEqual(source.width, 512, name)
            XCTAssertEqual(source.height, 512, name)
            let pixels = try rgbaPixels(for: source, side: 512)
            XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 },
                          "The actual bundled wood source is opaque: \(name)")
            let tones: [Double] = stride(from: 0, to: pixels.count, by: 4).map { offset -> Double in
                let red = 0.2126 * Double(pixels[offset])
                let green = 0.7152 * Double(pixels[offset + 1])
                let blue = 0.0722 * Double(pixels[offset + 2])
                return red + green + blue
            }.sorted()
            let lowerDecile = tones[(tones.count - 1) / 10]
            let upperDecile = tones[(tones.count - 1) * 9 / 10]
            XCTAssertGreaterThan(upperDecile - lowerDecile, 5,
                                 "Bundled source must contain real material variation, not a placeholder fill: \(name)")
            sourceFields.append(Data(pixels))
        }
        XCTAssertNotEqual(sourceFields[0], sourceFields[1], "Paint and exposed wood need separate source fields")
        var cacheIdentities = Set<ObjectIdentifier>()
        for scheme: ColorScheme in [.light, .dark] {
            var sharedWood: UIImage?
            for role in ChristmasOrnamentRole.allCases {
                for color: StoneColor in [.black, .white] {
                    for kind in ChristmasOrnamentTexture.Kind.allCases {
                        let image = try XCTUnwrap(ChristmasOrnamentTexture.image(kind: kind, color: color,
                            role: role, scheme: scheme), "Missing actual runtime material must not pass via solid fallback")
                        let repeated = try XCTUnwrap(ChristmasOrnamentTexture.image(kind: kind, color: color,
                            role: role, scheme: scheme))
                        XCTAssertTrue(image === repeated, "Clock ticks must reuse the prepared image")
                        cacheIdentities.insert(ObjectIdentifier(image))
                        let source = try XCTUnwrap(image.cgImage)
                        XCTAssertEqual(source.width, 512)
                        XCTAssertEqual(source.height, 512)
                        XCTAssertGreaterThan(image.size.width, 0)
                        XCTAssertTrue(image.size.width.isFinite)
                        let pixels = try rgbaPixels(for: source, side: 512)
                        XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 },
                                      "The image actually used by the material remains opaque")
                        if kind == .bareWood {
                            if let sharedWood {
                                XCTAssertTrue(image === sharedWood,
                                    "Unpainted wood is shared across role and stone color within an appearance")
                            } else { sharedWood = image }
                        }
                    }
                }
            }
        }
        XCTAssertLessThanOrEqual(cacheIdentities.count, 10,
            "The finite role/color/appearance palette must not retain duplicate material maps")
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
            XCTAssertGreaterThan(max(contrast(stone.territoryMark, board.boardColor),
                                     contrast(board.scoreMarkOutline(on: nil), board.boardColor)), 3)
        }
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

    func testStudioTerritoryOwnersStayDistinctInBothAppearances() {
        for style: UIUserInterfaceStyle in [.light, .dark] {
            let board = SurroundTheme.surroundStudio.board(for: style == .dark ? .dark : .light)
            XCTAssertGreaterThanOrEqual(contrast(board.black.territoryMark, board.white.territoryMark,
                                                style: style), 12,
                                       "Territory owners must remain distinct in small filled squares")
            XCTAssertLessThan(luminance(board.black.territoryMark, style: style),
                              luminance(board.boardColor, style: style))
            XCTAssertGreaterThan(luminance(board.white.territoryMark, style: style),
                                 luminance(board.boardColor, style: style),
                                 "White ownership should read as light shell, not another dark pigment")
        }
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

    @MainActor
    func testStudioShoulderPreservesLargeFlatAndBlackStones() throws {
        let bundle = Bundle(for: Self.self)
        let black = try XCTUnwrap(UIImage(named: "SurroundStudioSlate0", in: bundle, compatibleWith: nil))
        let white = try XCTUnwrap(UIImage(named: "SurroundStudioClamshell0", in: bundle, compatibleWith: nil))
        for scheme: ColorScheme in [.light, .dark] {
            for theme in SurroundTheme.allCases {
                let expected: ImageStoneShading = switch theme {
                case .surroundStudio, .paperBlossoms: .clamshellShoulder
                case .frostPine: .iceEdge
                default: .artwork
                }
                XCTAssertEqual(theme.board(for: scheme).imageStoneShading, expected)
            }
            var board = SurroundTheme.surroundStudio.board(for: scheme)
            let tint = board.stoneImages?.tint ?? .white
            board.stoneImages = StoneImages(black: [black], white: [white], tint: tint)
            for color: StoneColor in [.black, .white] {
                for (diameter, shadow): (CGFloat, CGFloat) in [(7, 1), (13.99, 1), (20, 0),
                                                               (20, 1), (32, 1), (44, 1)] {
                    func render(_ shading: ImageStoneShading) throws -> (pixels: [UInt8], width: Int, height: Int) {
                        var appearance = board
                        appearance.imageStoneShading = shading
                        return try nativeMaterialPixels(Stone(color: color, shadowRadius: shadow)
                            .frame(width: diameter, height: diameter).padding(3)
                            .environment(\.boardAppearance, appearance)
                            .environment(\.colorScheme, scheme))
                    }
                    let actual = try render(.clamshellShoulder), plain = try render(.artwork)
                    if color == .black || diameter < 14 || diameter >= 32 || shadow == 0 {
                        XCTAssertEqual(actual.pixels, plain.pixels,
                                       "Only detailed phone-size white stones receive the accent")
                    } else {
                        XCTAssertGreaterThan(zip(actual.pixels, plain.pixels).filter { $0 != $1 }.count, 10)
                        // A visible edge change must leave the central grain
                        // and the face beneath last-move marks untouched.
                        let midX = actual.width / 2, midY = actual.height / 2
                        for y in (midY - 3)...(midY + 3) {
                            for x in (midX - 3)...(midX + 3) {
                                for channel in 0..<4 {
                                    let offset = (y * actual.width + x) * 4 + channel
                                    XCTAssertLessThanOrEqual(abs(Int(actual.pixels[offset]) - Int(plain.pixels[offset])), 1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testFeltMeadowAssetsKeepSeparateBoardAndEqualAlphaStoneFootprints() throws {
        let bundle = Bundle(for: SurroundThemeTests.self)
        func image(named name: String) throws -> UIImage {
            try XCTUnwrap(UIImage(named: name, in: bundle, compatibleWith: nil), name)
        }
        let landscape = try image(named: "FeltMeadowScene")
        let portrait = try image(named: "FeltMeadowScenePortrait")
        XCTAssertGreaterThan(landscape.size.width, landscape.size.height)
        XCTAssertGreaterThan(portrait.size.height, portrait.size.width)
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

    // Own and clear the target buffer so exact-zero projection checks do not
    // depend on the snapshot property's backing-store reuse for empty frames.
    @MainActor
    private func nativeMaterialPixelsUsingDirectContext<Content: View>(
        _ content: Content, scale: CGFloat = 3
    ) throws -> (pixels: [UInt8], width: Int, height: Int) {
        let renderer = ImageRenderer(content: content)
        var result: (pixels: [UInt8], width: Int, height: Int)?
        renderer.render(rasterizationScale: scale) { size, draw in
            let width = Int(ceil(size.width * scale)), height = Int(ceil(size.height * scale))
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            pixels.withUnsafeMutableBytes { bytes in
                guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                    XCTFail("Could not create direct native rendering context")
                    return
                }
                context.clear(CGRect(x: 0, y: 0, width: width, height: height))
                context.scaleBy(x: scale, y: scale)
                draw(context)
                context.flush()
            }
            result = (pixels, width, height)
        }
        return try withExtendedLifetime(renderer) { try XCTUnwrap(result) }
    }

    @MainActor
    private func nativeMaterialPixels<Content: View>(_ content: Content, scale: CGFloat = 3) throws
        -> (pixels: [UInt8], width: Int, height: Int) {
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
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

    func testChristmasKeepsakesRoomAssetsAreOpaqueSquareCompositions() throws {
        let bundle = Bundle(for: Self.self)
        let compositions = ChristmasKeepsakesRoomLayout.Composition.allCases
        let names = Set(compositions.map(\.assetName))
        XCTAssertEqual(compositions.count, 4)
        XCTAssertEqual(names, ["ChristmasKeepsakesRoomCompactPortrait", "ChristmasKeepsakesRoomCompactLandscape",
                               "ChristmasKeepsakesRoomRegularPortrait", "ChristmasKeepsakesRoomRegularLandscape"])
        var roomPixels: [Data] = []
        for name in names.sorted() {
            let image = try XCTUnwrap(UIImage(named: name, in: bundle, compatibleWith: nil), name)
            let source = try XCTUnwrap(image.cgImage, name)
            XCTAssertEqual(source.width, source.height, "\(name): composition must match the square crop model")
            let pixels = try rgbaPixels(for: source, side: 128)
            XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 },
                          "\(name): gifts, contact shadows and tabletop form one opaque room")
            roomPixels.append(Data(pixels))
        }
        XCTAssertEqual(Set(roomPixels).count, 4,
                       "Each aspect family must package its own composition rather than four aliases of one crop")
    }

    func testChristmasKeepsakesTreeAssetIsCachedAndTransparent() throws {
        let image = try XCTUnwrap(ChristmasKeepsakesTreeAssets.image)
        XCTAssertTrue(image === ChristmasKeepsakesTreeAssets.image, "Scene updates reuse one decoded tree")
        let source = try XCTUnwrap(image.cgImage)
        XCTAssertGreaterThan(source.height, source.width, "The tree is upright portrait artwork")
        let side = 128
        let pixels = try rgbaPixels(for: source, side: side)
        let alphas = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
        XCTAssertGreaterThan(alphas.filter { $0 == 0 }.count, side * side / 10,
                             "Open space around the boughs must reveal the existing room")
        XCTAssertGreaterThan(alphas.filter { $0 > 240 }.count, side * side / 10,
                             "The tree needs real opaque foliage, not only translucent haze")
        for size in [CGSize(width: 402, height: 874), CGSize(width: 874, height: 402),
                     CGSize(width: 834, height: 1210), CGSize(width: 1210, height: 834)] {
            let frame = ChristmasKeepsakesTreeLayout(size: size, artworkSize: image.size).frame
            let visible = frame.intersection(CGRect(origin: .zero, size: size))
            let minX = max(0, Int(floor((visible.minX - frame.minX) / frame.width * CGFloat(side))))
            let maxX = min(side, Int(ceil((visible.maxX - frame.minX) / frame.width * CGFloat(side))))
            let minY = max(0, Int(floor((visible.minY - frame.minY) / frame.height * CGFloat(side))))
            let maxY = min(side, Int(ceil((visible.maxY - frame.minY) / frame.height * CGFloat(side))))
            var visibleInk = 0
            for y in minY..<maxY {
                for x in minX..<maxX where pixels[(y * side + x) * 4 + 3] > 128 {
                    visibleInk += 1
                }
            }
            XCTAssertGreaterThan(visibleInk, (maxX - minX) * (maxY - minY) / 100,
                                 "The narrow native crop must expose actual boughs in \(size)")
        }
    }

    func testChristmasKeepsakesAssetsKeepOpaqueBoardAndEqualGlassFootprints() throws {
        let bundle = Bundle(for: Self.self)
        func image(_ suffix: String) throws -> UIImage {
            let name = "ChristmasKeepsakes" + suffix
            return try XCTUnwrap(UIImage(named: name, in: bundle, compatibleWith: nil), name)
        }
        let pixels = try rgbaPixels(for: XCTUnwrap(image("BoardSurface").cgImage), side: 128)
        XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 },
                      "The board remains a separate opaque playing surface")
        try assertEqualAlphaStoneFootprints(StoneImages(
            black: [try image("RubyStone")], white: [try image("IvoryStone")]
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
        XCTAssertEqual(texture.opacity, 1, "Existing board textures retain their full strength by default")
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

    func testEngravedGridKeepsPlayingIntersectionsAndStandardStarPoints() {
        for theme in SurroundTheme.allCases {
            for scheme: ColorScheme in [.light, .dark] {
                let style = theme.board(for: scheme).gridStyle
                for cell: CGFloat in [7, 13, 13.99, 14, 20, 48] {
                    XCTAssertEqual(style.usesEngraving(at: cell), theme == .frostPine && cell >= 14)
                }
            }
        }
        for (width, height) in [(2, 3), (9, 9), (13, 13), (19, 19), (9, 19), (19, 9)] {
            for cell: CGFloat in [13.99, 14, 20, 48] {
                let grid = EngravedGridGeometry(width: width, height: height, cellSize: cell)
                let expected = CGRect(x: cell / 2, y: cell / 2,
                                      width: CGFloat(width - 1) * cell, height: CGFloat(height - 1) * cell)
                XCTAssertEqual(grid.gridRect, expected)
                XCTAssertEqual(grid.outlinePath.boundingRect, expected)
                let expectedStars = width == height ? (width == 19 ? 9 : 5) : 0
                XCTAssertEqual(grid.starCenters.count, expectedStars)
                for center in grid.starCenters {
                    XCTAssertTrue(expected.contains(center))
                    for coordinate in [center.x, center.y] {
                        let index = coordinate / cell - 0.5
                        XCTAssertEqual(index, index.rounded(), accuracy: 0.000001,
                                       "Recessed stars remain centered on playing intersections")
                    }
                }
                if expectedStars > 0 {
                    XCTAssertTrue(grid.starCenters.contains(CGPoint(x: CGFloat(width) * cell / 2,
                                                                    y: CGFloat(height) * cell / 2)))
                    let inset = width == 9 ? 2 : 3
                    XCTAssertTrue(grid.starCenters.contains(CGPoint(x: (CGFloat(inset) + 0.5) * cell,
                                                                    y: (CGFloat(inset) + 0.5) * cell)))
                }
            }
        }
    }

    func testEngravedGridChipsStayBoundedAndStableWhileResizing() {
        for (width, height) in [(9, 19), (19, 9)] {
            var prior: [[CGPoint]]?
            var priorCell: CGFloat = 0
            for cell: CGFloat in [14, 20, 40] {
                let grid = EngravedGridGeometry(width: width, height: height, cellSize: cell)
                let paths = polygons(in: grid.chippedPath)
                XCTAssertFalse(paths.isEmpty)
                XCTAssertEqual(paths, polygons(in: grid.chippedPath), "Redraws must not reseed ice chips")
                XCTAssertTrue(grid.gridRect.insetBy(dx: -1.65, dy: -1.65).contains(grid.chippedPath.boundingRect),
                              "Chips stay within a narrow strip of the playing grid")
                let edges = paths.filter { $0.count > 4 }
                XCTAssertFalse(edges.isEmpty, "The relief must contain irregular edges, not just clean rectangles")
                let fineEdges = polygons(in: RaggedGridGeometry(width: width, height: height,
                    cellSize: cell, lineScale: 1).path).filter { $0.count > 4 }
                XCTAssertLessThan(edges.reduce(0) { $0 + $1.count }, fineEdges.reduce(0) { $0 + $1.count },
                                  "Ice chips need longer facets than the fine scratched-grid texture")
                for edge in edges {
                    let spanX = edge.map(\.x).max()! - edge.map(\.x).min()!
                    let spanY = edge.map(\.y).max()! - edge.map(\.y).min()!
                    let horizontal = spanX > spanY
                    let across = edge.map { horizontal ? $0.y : $0.x }
                    let center = (across.min()! + across.max()!) / 2
                    let distances = across.map { abs($0 - center) }
                    XCTAssertGreaterThan(distances.max()! - distances.min()!, 0.1,
                                         "Each cut needs visible edge variation around its straight core")
                    XCTAssertLessThan(distances.max()!, 1.65)
                    let gridCenter = ((center / cell - 0.5).rounded() + 0.5) * cell
                    let asymmetricPairs = (0..<(edge.count / 2)).filter { index in
                        let a = edge[index], b = edge[edge.count - 1 - index]
                        let acrossA = horizontal ? a.y : a.x
                        let acrossB = horizontal ? b.y : b.x
                        return abs(acrossA + acrossB - 2 * gridCenter) > 0.08
                    }.count
                    XCTAssertGreaterThan(asymmetricPairs, edge.count / 8,
                                         "Opposite ice-cut lips must not repeatedly form mirrored beads")
                }
                if let prior {
                    XCTAssertEqual(prior.count, paths.count)
                    for (before, after) in zip(prior, paths) where before.count > 4 {
                        XCTAssertEqual(before.count, after.count)
                        let horizontal = before.map(\.x).max()! - before.map(\.x).min()!
                            > before.map(\.y).max()! - before.map(\.y).min()!
                        if cell >= 40 {
                            let oldAcross = before.map { horizontal ? $0.y : $0.x }
                            let newAcross = after.map { horizontal ? $0.y : $0.x }
                            let oldWidth = oldAcross.max()! - oldAcross.min()!
                            let newWidth = newAcross.max()! - newAcross.min()!
                            XCTAssertGreaterThan(newWidth, oldWidth + 0.4,
                                                 "Large-board facets must retain a visibly wider cut than phone facets")
                        }
                        for (a, b) in zip(before, after) {
                            // Path quantizes its stored points. Compare in
                            // the resized board's points, allowing less than
                            // one thousandth of a pixel even at 3x scale.
                            XCTAssertEqual((horizontal ? a.x : a.y) * cell / priorCell,
                                           horizontal ? b.x : b.y, accuracy: 0.0001,
                                           "Chips stay attached to their cells while resizing")
                        }
                    }
                }
                prior = paths
                priorCell = cell
            }
        }
    }

    @MainActor
    func testEngravedGridNativeCoreIsContinuousAndCompactBoardsStayPlain() throws {
        let background = Color(red: 0.72, green: 0.80, blue: 0.85)
        let pigment = Color(red: 0.25, green: 0.35, blue: 0.42)
        for (width, height) in [(9, 19), (19, 9)] {
            for cell: CGFloat in [7, 13.99, 14, 20, 32] {
                let grid = EngravedGridGeometry(width: width, height: height, cellSize: cell)
                let result = try nativeMaterialPixels(background.overlay {
                    EngravedGobanGrid(geometry: grid, color: pigment)
                }.frame(width: CGFloat(width) * cell, height: CGFloat(height) * cell))
                let base = Array(result.pixels[0..<4])
                if cell < 14 {
                    // A fractional frame can antialias its outer pixel row.
                    // Compare the exact same native frame without engraving,
                    // not an assumed uniformly filled pixel rectangle.
                    let plain = try nativeMaterialPixels(background
                        .frame(width: CGFloat(width) * cell, height: CGFloat(height) * cell))
                    XCTAssertEqual(result.pixels, plain.pixels,
                                   "The mounted engraving layer must be transparent below 14 pt")
                    continue
                }
                func brightness(at x: Int, _ y: Int) -> Double {
                    let offset = (y * result.width + x) * 4
                    return (Double(result.pixels[offset]) + Double(result.pixels[offset + 1])
                            + Double(result.pixels[offset + 2])) / 3
                }
                func darkestNear(_ point: CGPoint) -> Double {
                    let x = Int(point.x * 3), y = Int(point.y * 3)
                    return ((y - 1)...(y + 1)).flatMap { py in
                        ((x - 1)...(x + 1)).map { brightness(at: $0, py) }
                    }.min()!
                }
                let backgroundBrightness = (Double(base[0]) + Double(base[1]) + Double(base[2])) / 3
                // Quarter-cell samples include every intersection and the
                // spans between them, including all four outer edges.
                for row in 0..<height {
                    for sample in 0...((width - 1) * 4) {
                        let point = CGPoint(x: (0.5 + CGFloat(sample) / 4) * cell,
                                            y: (CGFloat(row) + 0.5) * cell)
                        XCTAssertLessThan(darkestNear(point), backgroundBrightness - 25,
                                          "A continuous core must survive its relief at \(cell) pt")
                    }
                }
                for column in 0..<width {
                    for sample in 0...((height - 1) * 4) {
                        let point = CGPoint(x: (CGFloat(column) + 0.5) * cell,
                                            y: (0.5 + CGFloat(sample) / 4) * cell)
                        XCTAssertLessThan(darkestNear(point), backgroundBrightness - 25)
                    }
                }
                for row in 0..<(height - 1) {
                    for column in 0..<(width - 1) {
                        let x = Int(CGFloat(column + 1) * cell * 3)
                        let y = Int(CGFloat(row + 1) * cell * 3)
                        let offset = (y * result.width + x) * 4
                        XCTAssertEqual(Array(result.pixels[offset..<(offset + 4)]), base,
                                       "Engraving leaves empty cell interiors untouched")
                    }
                }
            }
        }
    }

    @MainActor
    func testEngravedGridNativeReliefHasUpperShadeAndLowerLight() throws {
        // Calibrate the bitmap row direction independently of engraving;
        // ImageRenderer and the CGContext pixel reader may use opposite axes.
        let orientation = try nativeMaterialPixels(VStack(spacing: 0) {
            Color.white.frame(height: 6)
            Color.black.frame(height: 6)
        }.frame(width: 12, height: 12))
        let firstHalfIsTop = orientation.pixels[(9 * orientation.width + 18) * 4] > 127
        let background = Color(red: 0.72, green: 0.80, blue: 0.85)
        let pigment = Color(red: 0.25, green: 0.35, blue: 0.42)

        for cell: CGFloat in [14, 20, 40] {
            // A rectangular board has no star dimples to contaminate the
            // relief samples midway along horizontal and vertical cuts.
            let grid = EngravedGridGeometry(width: 9, height: 10, cellSize: cell)
            let result = try nativeMaterialPixels(background.overlay {
                EngravedGobanGrid(geometry: grid, color: pigment)
            }.frame(width: 9 * cell, height: 10 * cell))
            func brightness(at point: CGPoint) -> Double {
                let x = Int(point.x * 3), logicalY = Int(point.y * 3)
                let y = firstHalfIsTop ? logicalY : result.height - 1 - logicalY
                let offset = (y * result.width + x) * 4
                return (Double(result.pixels[offset]) + Double(result.pixels[offset + 1])
                        + Double(result.pixels[offset + 2])) / 3
            }
            let field = brightness(at: CGPoint(x: 3 * cell, y: 3 * cell))
            for horizontal in [true, false] {
                let middle = horizontal ? CGPoint(x: 3 * cell, y: 2.5 * cell)
                                        : CGPoint(x: 2.5 * cell, y: 3 * cell)
                func wall(_ sign: CGFloat) -> [Double] {
                    (-3...3).flatMap { along in (0..<4).map { index in
                        // Sample off the pigment core over a one-point band,
                        // across several chips: a single chipped lip can be
                        // narrow, but the cut must retain directional relief.
                        let offset = sign * (0.5 + CGFloat(index) / 3)
                        let advance = CGFloat(along) * cell / 12
                        return brightness(at: CGPoint(x: middle.x + (horizontal ? advance : offset),
                                                      y: middle.y + (horizontal ? offset : advance)))
                    } }
                }
                XCTAssertLessThan(try XCTUnwrap(wall(-1).min()), field - 8,
                                  "The upper/left recess wall must visibly shade the field at \(cell) pt")
                XCTAssertGreaterThan(try XCTUnwrap(wall(1).max()), field + 8,
                                     "The lower/right recess wall must catch light at \(cell) pt")
                let edge = (0..<24).map { index in
                    let advance = (CGFloat(index) / 24 - 0.5) * cell / 2
                    return brightness(at: CGPoint(x: middle.x + (horizontal ? advance : 0.75),
                                                  y: middle.y + (horizontal ? 0.75 : advance)))
                }
                XCTAssertGreaterThan(try XCTUnwrap(edge.max()) - XCTUnwrap(edge.min()), 5,
                                     "Native relief must vary along the ice cut rather than form a clean rail")
                if cell >= 40 {
                    let wideLip = (1..<8).flatMap { span in (0..<24).map { index in
                        // Sample between crossings, beyond the narrow phone
                        // cut. Several spans prevent one seeded chip from
                        // deciding the result, without counting intersections.
                        let along = (CGFloat(span) + (CGFloat(index) / 24 - 0.5) / 2) * cell
                        return brightness(at: CGPoint(x: horizontal ? along : middle.x + 1.5,
                                                      y: horizontal ? middle.y + 1.5 : along))
                    } }
                    XCTAssertGreaterThan(try XCTUnwrap(wideLip.max()), field + 8,
                                         "Large cuts need visible native relief beyond a hairline-width shoulder")
                }
            }
        }
    }

    @MainActor
    func testEngravedStarDimplesStaySmallAndCentered() throws {
        for cell: CGFloat in [7, 13.99, 14, 20, 32] {
            let grid = EngravedGridGeometry(width: 9, height: 9, cellSize: cell)
            func render(height: Int) throws -> (pixels: [UInt8], width: Int, height: Int) {
                try nativeMaterialPixels(Color(red: 0.72, green: 0.80, blue: 0.85).overlay {
                    EngravedGobanGrid(geometry: EngravedGridGeometry(width: 9, height: height, cellSize: cell),
                                      color: Color(red: 0.25, green: 0.35, blue: 0.42))
                }.frame(width: 9 * cell, height: 9 * cell))
            }
            let dimples = try render(height: 9)
            // The rectangular board has no stars but the same local grid
            // through all five sampled centers. Its different border lies
            // well outside these patches, isolating the actual dimple paint.
            let plain = try render(height: 10)
            XCTAssertEqual(dimples.width, plain.width)
            XCTAssertEqual(dimples.height, plain.height)
            if cell < 14 {
                XCTAssertEqual(dimples.pixels, plain.pixels,
                               "Small boards cannot acquire either a dimple core or relief")
                continue
            }
            XCTAssertLessThan(grid.dimpleDiameter, cell / 3,
                              "A visible star remains local to its intersection")
            XCTAssertLessThanOrEqual(grid.dimpleDiameter, 5.5,
                                     "The recessed footprint stays bounded on larger boards")
            for center in grid.starCenters {
                let centerX = Double(center.x * 3), centerY = Double(center.y * 3)
                let radius = Double(grid.dimpleDiameter * 3 / 2)
                let reach = Int(ceil(radius + 3))
                var changed = 0, farthestChange = 0.0, darkestCore = 255.0
                var solidCoreQuadrants = Set<Int>()
                func brightness(_ pixels: [UInt8], offset: Int) -> Double {
                    (Double(pixels[offset]) + Double(pixels[offset + 1]) + Double(pixels[offset + 2])) / 3
                }
                let centerOffset = (Int(centerY) * dimples.width + Int(centerX)) * 4
                let centerBrightness = brightness(dimples.pixels, offset: centerOffset)
                XCTAssertLessThan(centerBrightness, brightness(plain.pixels, offset: centerOffset) - 15,
                                  "The hoshi center must be visibly darker than an ordinary grid crossing")
                for y in (Int(centerY) - reach)...(Int(centerY) + reach) {
                    for x in (Int(centerX) - reach)...(Int(centerX) + reach) {
                        let offset = (y * dimples.width + x) * 4
                        let dx = Double(x) + 0.5 - centerX, dy = Double(y) + 0.5 - centerY
                        let distance = hypot(dx, dy)
                        let delta = (0..<4).map {
                            abs(Int(dimples.pixels[offset + $0]) - Int(plain.pixels[offset + $0]))
                        }.max()!
                        if delta > 1 {
                            changed += 1
                            farthestChange = max(farthestChange, distance)
                        }
                        if distance < radius * 0.45 {
                            darkestCore = min(darkestCore, brightness(dimples.pixels, offset: offset))
                        }
                        // A plain crossing is already dark at its center.
                        // Require a solid dark disc in all four diagonals,
                        // beyond a 1.5 pt radius on phone-sized and larger
                        // boards, and off both grid axes.
                        // A small dark intersection or bright lip alone fails.
                        let minimumRadius: Double = cell >= 20 ? 4.5 : 3
                        let maximumRadius: Double = cell >= 20 ? 5.4 : 4.2
                        let axisClearance: Double = cell >= 20 ? 3 : 2
                        if distance >= minimumRadius, distance <= maximumRadius,
                           abs(dx) >= axisClearance, abs(dy) >= axisClearance {
                            let dark = brightness(dimples.pixels, offset: offset)
                            if dark <= centerBrightness + 8,
                               brightness(plain.pixels, offset: offset) - dark > 8 {
                                solidCoreQuadrants.insert((dx > 0 ? 1 : 0) + (dy > 0 ? 2 : 0))
                            }
                        }
                    }
                }
                XCTAssertGreaterThan(changed, 4, "A visible recess distinguishes a star from a plain intersection")
                XCTAssertLessThan(darkestCore, 140, "The dimple keeps a dark center on its intersection")
                XCTAssertEqual(solidCoreQuadrants.count, 4,
                               "A hoshi must show a substantial round dark core beyond the ordinary crossing")
                XCTAssertLessThanOrEqual(farthestChange, radius + 1.25,
                                         "Recess relief stays inside the small footprint plus antialiasing")
            }
        }
    }

    func testRaggedGridAppearsOnDetailedGardenAndReefBoards() {
        for theme in SurroundTheme.allCases {
            let usesRaggedGrid = theme == .rakedGarden || theme == .reefLight
            for scheme: ColorScheme in [.light, .dark] {
                let style = theme.board(for: scheme).gridStyle
                XCTAssertFalse(style.usesRaggedEdges(at: 13.99))
                XCTAssertEqual(style.usesRaggedEdges(at: 14), usesRaggedGrid)
                XCTAssertEqual(style.usesRaggedEdges(at: 48), usesRaggedGrid)
            }
        }
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
        let explicitDefaults = RaggedGridGeometry(width: 9, height: 13, cellSize: 20, lineScale: 1.6,
                                                  edgeAmplitude: 0.38, edgeSamplesPerCell: 20,
                                                  independentEdges: false)
        XCTAssertEqual(first, polygons(in: explicitDefaults.path),
                       "Configurable ice chips must not change the existing scratched-grid defaults")
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
