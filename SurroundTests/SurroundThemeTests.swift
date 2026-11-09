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
        for theme: SurroundTheme in [.surroundStudio, .christmasKeepsakes] {
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
                                    SurroundTheme.christmasKeepsakes.board(for: .dark).boardDepth]
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
                          XCTUnwrap(SurroundTheme.christmasKeepsakes.board(for: .dark).boardDepth)]
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

    func testFrostPineAppearanceAndAnalysisStayReadable() throws {
        assertAdaptiveColorsFollowRepeatedTraitChanges(.frostPine)
        try assertNightAnalysisMarksRemainReadable(.frostPine)
    }

    func testFrostPineDayStonesBrightenWithoutChangingNightArtworkOrSilhouettes() throws {
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
                let after = try rgbaPixels(for: light, side: source.width)
                XCTAssertEqual(try rgbaPixels(for: dark, side: source.width), before,
                               "Night keeps the original ice artwork")
                XCTAssertEqual(stride(from: 3, to: before.count, by: 4).map { before[$0] },
                               stride(from: 3, to: after.count, by: 4).map { after[$0] },
                               "Daylight grading must preserve the opaque interior and transparent edge")
                func brightness(_ pixels: [UInt8], at offset: Int) -> Double {
                    0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1])
                        + 0.0722 * Double(pixels[offset + 2])
                }
                let middleTones = stride(from: 0, to: before.count, by: 4).filter {
                    before[$0 + 3] == 255 && (20...220).contains(brightness(before, at: $0))
                }
                XCTAssertGreaterThan(middleTones.count, 1000)
                let lift = middleTones.reduce(0.0) {
                    $0 + brightness(after, at: $1) - brightness(before, at: $1)
                } / Double(max(1, middleTones.count))
                XCTAssertGreaterThan(lift, 8, "Both ice colors need a visible daylight lift")
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
                    XCTAssertEqual(board.boardColor, theme.flowingInkUsesColor ? Color(themeHex: 0xDDE7DB) : .white,
                                   "An explicit Light appearance preserves the original concept")
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
            XCTAssertEqual(SurroundTheme.flowingInkJade.board(for: scheme), SurroundTheme.flowingInkJadePlain.board(for: scheme))
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

    /// Exercise the exact outline used by the production clock card, rather
    /// than only checking an unused palette token. Header and score cards use
    /// this same view. The UI audit separately exercises the system's read-only
    /// Increase Contrast environment through the supported simulator setting.
    @MainActor
    func testMatteThemeRunningClockOutlineRemainsVisibleAtEverySize() throws {
        for theme: SurroundTheme in [.flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain, .paperBlossoms] {
            for scheme: ColorScheme in [.light, .dark] {
                for color: StoneColor in [.black, .white] {
                    for size in [CGSize(width: 88, height: 32), CGSize(width: 132, height: 48),
                                 CGSize(width: 178, height: 88)] {
                        for scale: CGFloat in [2, 3] {
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
                                    XCTAssertGreaterThanOrEqual(contrast(pixel(Int(scale)), interior), 3, detail)
                                }
                                widths.append((0..<Int(6 * scale)).filter {
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

    func testPaperBlossomsKeepsPaperAndFoldedStonesReadableInBothAppearances() throws {
        let theme = SurroundTheme.paperBlossoms
        XCTAssertTrue(theme.isDebugOnly)
        XCTAssertEqual(theme.title, "Paper Blossoms")
        XCTAssertNil(theme.colorScheme, "The surrounding interface follows the chosen appearance")
        for scheme: ColorScheme in [.light, .dark] {
            let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
            let board = theme.board(for: scheme)
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
        let bundle = Bundle(for: Self.self)
        let black = try XCTUnwrap(UIImage(named: "PaperBlossomsBlackStone", in: bundle, compatibleWith: nil))
        let white = try XCTUnwrap(UIImage(named: "PaperBlossomsWhiteStone", in: bundle, compatibleWith: nil))
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
            var lifted = SurroundTheme.paperBlossoms.board(for: scheme)
            // Assets live in the unit-test bundle, not the app's main bundle.
            lifted.stoneImages = StoneImages(black: [black], white: [white],
                tint: scheme == .dark ? Color(themeHex: 0xE8DFD0) : .white, blackFaceGain: 1.3)
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
    func testPaperBlossomsTurnedCornerKeepsTextAndTurnRingReadable() throws {
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
                    let ring = try nativeMaterialPixels(GameDetailMatteClockOutline(
                        color: color, isRunning: true, cornerRadius: radius, paperCompact: compact)
                        .frame(width: size.width, height: size.height)
                        .environment(\.surroundTheme, theme)
                        .environment(\.colorScheme, scheme), scale: scale)
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
                    var perimeterSamples = 0, redUnderPerimeter = 0, cornerRingSamples = 0
                    var ringOverTransparency = 0, ringOutsideFacePerimeter = 0
                    var nonOpaqueRingPixels: [String] = []
                    var minimumRingContrast = Double.infinity
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
                            if ring.pixels[offset + 3] == 255 {
                                let perimeterCoverage = protectedPerimeter.pixels[offset + 3]
                                if perimeterCoverage == 0 { ringOutsideFacePerimeter += 1 }
                                // At the three ordinary rounded corners, the
                                // native 3pt stroke can be opaque while the
                                // 4pt mask is 254 and clipped paper is 250. Those
                                // are antialiased edge samples, not paper holes.
                                if alpha == 0 || (perimeterCoverage == 255 && alpha != 255) {
                                    ringOverTransparency += 1
                                    if nonOpaqueRingPixels.count < 12 {
                                        nonOpaqueRingPixels.append("(\(x),\(y)):alpha=\(alpha),interior=\(interior.pixels[offset + 3]),perimeter=\(protectedPerimeter.pixels[offset + 3])")
                                    }
                                }
                                let ink = pixelLuminance(ring.pixels, offset)
                                let backing = pixelLuminance(rendered.pixels, offset)
                                let ratio = (max(ink, backing) + 0.05) / (min(ink, backing) + 0.05)
                                minimumRingContrast = min(minimumRingContrast, ratio)
                                if point.x > size.width - fold - 4 && point.y > size.height - fold - 4 {
                                    cornerRingSamples += 1
                                }
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
                    XCTAssertEqual(redUnderPerimeter, 0, "The ring must stay on ink/ivory, including the crease: \(detail)")
                    XCTAssertGreaterThan(cornerRingSamples, 4, "The native ring follows the turned corner: \(detail)")
                    XCTAssertEqual(ringOutsideFacePerimeter, 0,
                                   "The native ring must follow the paper's crease perimeter: \(detail)")
                    XCTAssertEqual(ringOverTransparency, 0,
                                   "The turn ring stays inside the paper: \(detail); \(nonOpaqueRingPixels)")
                    XCTAssertGreaterThanOrEqual(minimumRingContrast, 3,
                                               "The actual ring must contrast beside the red reverse: \(detail)")
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
        #else
        XCTAssertEqual(SurroundTheme.current(storedID: "nebulaPearl"), .nebulaPearl)
        XCTAssertEqual(SurroundTheme.current(storedID: "rakedGarden"), .rakedGarden)
        XCTAssertEqual(SurroundTheme.current(storedID: "surroundStudio"), .surroundStudio)
        XCTAssertEqual(SurroundTheme.current(storedID: "frostPine"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: "feltMeadow"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: "nightGarden"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: "christmasKeepsakes"), .standard)
        XCTAssertEqual(SurroundTheme.current(storedID: "paperBlossoms"), .standard)
        #endif
    }

    /// Classic and three scenes ship, in the pickers' order; Debug builds
    /// append the unreleased themes.
    func testPickersOfferTheReleasedThemesFirst() {
        XCTAssertEqual(SurroundTheme.released, [.standard, .surroundStudio, .rakedGarden, .nebulaPearl])
        let unreleased: [SurroundTheme] = [.frostPine, .feltMeadow, .nightGarden, .christmasKeepsakes,
                                          .paperBlossoms, .flowingInk, .flowingInkJade, .flowingInkJadePlain, .flowingInkPlain]
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

    func testChristmasKeepsakesCabochonPreservesAuthoredColorsAndIvory() throws {
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
                               "Keep the cabochon's authored color and alpha, and the unchanged ivory source")
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
            func render(light: Bool, lightAboveBoards: Bool = false) throws
                -> (pixels: [UInt8], width: Int, height: Int) {
                try nativeMaterialPixels(ZStack(alignment: .topLeading) {
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
                .environment(\.boardAppearance, appearance)
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
            var maximumChannelDelta = changedInside
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
                                if isShoulder, pixelDelta <= 1,
                                   lit.pixels[offset + 3] == baseline.pixels[offset + 3] {
                                    roundedShoulderPixels[index] += 1
                                } else {
                                    unexpectedChanges[index] += 1
                                }
                                if changedSamples.count < 40 { changedSamples.append([index, x, y]) }
                            }
                            if (0..<4).contains(where: {
                                abs(Int(unprotected.pixels[offset + $0]) - Int(baseline.pixels[offset + $0])) > 1
                            }) {
                                unprotectedChanges[index] += 1
                            }
                        }
                    }
                    if !inSlab && differs { changedOutside += 1 }
                }
            }
            // iOS 26.5 rounds five tinted-image shoulder pixels by one RGB
            // byte when the filtered room field is present. Untinted images
            // and solid stones are exact. Permit this only in the outer 20%
            // of the detailed stone radius, at <= 0.5% of those pixels.
            // Pigment, stone centers, compact stones and all alpha stay exact.
            let roundingFractions = frames.indices.map {
                Double(roundedShoulderPixels[$0]) / Double(max(1, shoulderPixels[$0]))
            }
            if frames.indices.contains(where: { unexpectedChanges[$0] > 0 || roundingFractions[$0] > 0.005 }) {
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
                    "repeated_baseline_identical": repeated.pixels == baseline.pixels,
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
                XCTAssertLessThanOrEqual(roundingFractions[index], 0.005,
                                         "One-byte RGB rounding must remain sparse within stone shoulders")
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
                if theme == .surroundStudio || theme == .feltMeadow || theme == .nightGarden || theme == .christmasKeepsakes || theme == .paperBlossoms {
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
        if theme == .surroundStudio || theme == .feltMeadow || theme == .nightGarden || theme == .christmasKeepsakes || theme == .paperBlossoms {
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
        // columns have 8 pt. The header has no spare outside strip for a ribbon.
        let cases: [(name: String, role: ChristmasOrnamentRole, size: CGSize,
                     inset: CGSize, decoration: Bool, compact: Bool)] = [
            ("Home clock", .clock, CGSize(width: 140, height: 28), CGSize(width: 9, height: 5), false, true),
            ("inline clock", .clock, CGSize(width: 320, height: 34), CGSize(width: 8, height: 6), false, true),
            ("compact clock", .clock, CGSize(width: 160, height: 52), CGSize(width: 8, height: 4), true, false),
            ("full clock", .clock, CGSize(width: 190, height: 96), CGSize(width: 12, height: 4), true, false),
            ("narrow clock", .clock, CGSize(width: 104, height: 144), CGSize(width: 10, height: 8), false, true),
            ("wide clock", .clock, CGSize(width: 420, height: 96), CGSize(width: 12, height: 4), true, false),
            ("large clock", .clock, CGSize(width: 680, height: 144), CGSize(width: 12, height: 4), true, false),
            ("row player", .player, CGSize(width: 156, height: 52), CGSize(width: 4, height: 8), true, false),
            ("short row player", .player, CGSize(width: 108, height: 52), CGSize(width: 4, height: 8), true, false),
            ("compact column player", .player, CGSize(width: 126, height: 84), CGSize(width: 5, height: 5), false, true),
            ("full vertical player", .player, CGSize(width: 156, height: 144), CGSize(width: 8, height: 8), false, true),
            ("wide vertical player", .player, CGSize(width: 240, height: 160), CGSize(width: 8, height: 8), false, true),
            // The header's 32 pt avatar and single name/rank line are vertically
            // centered in the 44 pt hit target; its decorative side tab is off.
            ("header player", .player, CGSize(width: 220, height: 44), CGSize(width: 4, height: 8), false, true)
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
                            attachment: .leading, showsDecoration: sample.decoration,
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
                                "Fallback is the exact solid outline with no bevel, grain or cord: \(message)")
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
    func testChristmasKeepsakeOrnamentsKeepVisibleWoodAndSafeAttachments() throws {
        let scale = 3, padding = 12
        // Caller-selected profiles, not a height heuristic. The regular clock
        // and row player may have depth/cords; constrained surfaces keep all
        // ornament detail inside their original bounds.
        let cases: [(role: ChristmasOrnamentRole, size: CGSize, inset: CGSize, compact: Bool)] = [
            (.clock, CGSize(width: 140, height: 28), CGSize(width: 9, height: 5), true),
            (.clock, CGSize(width: 160, height: 52), CGSize(width: 8, height: 4), false),
            (.clock, CGSize(width: 190, height: 96), CGSize(width: 12, height: 4), false),
            (.clock, CGSize(width: 104, height: 144), CGSize(width: 10, height: 8), true),
            (.player, CGSize(width: 156, height: 52), CGSize(width: 4, height: 8), false),
            (.player, CGSize(width: 126, height: 84), CGSize(width: 5, height: 5), true),
            (.player, CGSize(width: 156, height: 144), CGSize(width: 8, height: 8), true),
            (.player, CGSize(width: 220, height: 44), CGSize(width: 4, height: 8), true)
        ]
        for scheme: ColorScheme in [.light, .dark] {
            for color: StoneColor in [.black, .white] {
                for role in ChristmasOrnamentRole.allCases {
                    for sample in cases where sample.role == role {
                        let size = sample.size
                        func render(_ attachment: ChristmasOrnamentAttachment, decorated: Bool = true,
                                    detailed: Bool = true) throws -> (pixels: [UInt8], width: Int, height: Int) {
                            try nativeMaterialPixels(ChristmasOrnamentMaterial(color: color, role: role,
                                attachment: attachment, showsDecoration: decorated,
                                colorScheme: scheme, showsDetail: detailed, compact: sample.compact)
                                .frame(width: size.width, height: size.height).padding(CGFloat(padding))
                                .environment(\.colorScheme, scheme))
                        }
                        let plain = try render(.none)
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
                                let edgeOffset = (edgeY * plain.width + x) * 4
                                let faceOffset = (faceY * plain.width + x) * 4
                                let difference = (0..<3).map {
                                    abs(Int(plain.pixels[edgeOffset + $0]) - Int(plain.pixels[faceOffset + $0]))
                                }.max()!
                                if difference >= 8 { visibleEdge += 1 }
                                edgeCount += 1
                                edgeTones.append(encodedLuma(plain.pixels, edgeOffset))
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
                                        value += encodedLuma(plain.pixels, (py * plain.width + px) * 4)
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

                        let leading = try render(.leading), trailing = try render(.trailing)
                        let suppressed = try render(.leading, decorated: false)
                        let fallback = try render(.leading, detailed: false)
                        XCTAssertEqual(suppressed.pixels, plain.pixels,
                            "Suppressing a gutter cord must remove it completely: \(message)")
                        var contentDifference = 0
                        for y in (padding + Int(sample.inset.height)) * scale..<(padding + Int(size.height - sample.inset.height)) * scale {
                            for x in (padding + Int(sample.inset.width)) * scale..<(padding + Int(size.width - sample.inset.width)) * scale {
                                let offset = (y * plain.width + x) * 4
                                for channel in 0..<4 {
                                    contentDifference = max(contentDifference,
                                        max(abs(Int(leading.pixels[offset + channel]) - Int(plain.pixels[offset + channel])),
                                            abs(Int(trailing.pixels[offset + channel]) - Int(plain.pixels[offset + channel]))))
                                }
                            }
                        }
                        XCTAssertEqual(contentDifference, 0,
                            "Both attachment directions must leave the whole text face unchanged: \(message)")
                        var leadingInk = 0, trailingInk = 0, depthInk = 0
                        var undecoratedAlpha: UInt8 = 0, fallbackAlpha: UInt8 = 0
                        var wrongSideDifference = 0
                        var beyondGutterAlpha: UInt8 = 0
                        for y in 0..<plain.height {
                            for x in 0..<plain.width {
                                let outsideLeft = x < padding * scale
                                let outsideRight = x >= (padding + Int(size.width)) * scale
                                let outsideVertical = y < padding * scale || y >= (padding + Int(size.height)) * scale
                                guard outsideLeft || outsideRight || outsideVertical else { continue }
                                let offset = (y * plain.width + x) * 4
                                undecoratedAlpha = max(undecoratedAlpha, plain.pixels[offset + 3])
                                fallbackAlpha = max(fallbackAlpha, fallback.pixels[offset + 3])
                                if plain.pixels[offset + 3] >= 64 { depthInk += 1 }
                                let leadingDifference = abs(Int(leading.pixels[offset + 3]) - Int(plain.pixels[offset + 3]))
                                let trailingDifference = abs(Int(trailing.pixels[offset + 3]) - Int(plain.pixels[offset + 3]))
                                if outsideLeft {
                                    if leadingDifference >= 32 { leadingInk += 1 }
                                    wrongSideDifference = max(wrongSideDifference, trailingDifference)
                                }
                                if outsideRight {
                                    if trailingDifference >= 32 { trailingInk += 1 }
                                    wrongSideDifference = max(wrongSideDifference, leadingDifference)
                                }
                                // Regular ornaments legitimately extend their
                                // wood depth/contact shade and corner cord, but
                                // all details must stay in the 7pt free envelope.
                                if x < (padding - 7) * scale || x >= (padding + Int(size.width) + 7) * scale
                                    || y < (padding - 7) * scale || y >= (padding + Int(size.height) + 7) * scale {
                                    beyondGutterAlpha = max(beyondGutterAlpha,
                                        max(plain.pixels[offset + 3], max(leading.pixels[offset + 3], trailing.pixels[offset + 3])))
                                }
                            }
                        }
                        XCTAssertEqual(fallbackAlpha, 0, "Solid fallback has no cord, bevel or exterior decoration: \(message)")
                        XCTAssertEqual(wrongSideDifference, 0, "Cord must not change the opposite side's wood depth: \(message)")
                        XCTAssertEqual(beyondGutterAlpha, 0, "Depth and cord stay in the bounded free envelope: \(message)")
                        if sample.compact {
                            XCTAssertEqual(undecoratedAlpha, 0, "Constrained ornaments have no exterior depth: \(message)")
                            XCTAssertEqual(leading.pixels, plain.pixels, "Compact profile suppresses even explicitly requested cords: \(message)")
                            XCTAssertEqual(trailing.pixels, plain.pixels, "Compact profile suppresses both cord directions: \(message)")
                        } else {
                            XCTAssertGreaterThan(depthInk, 20, "Regular ornament thickness must visibly extend beyond the paint bounds: \(message)")
                            XCTAssertGreaterThan(leadingInk, 20, "Leading cord must add visible pixels beyond the wood depth: \(message)")
                            XCTAssertGreaterThan(trailingInk, 20, "Trailing cord must add visible pixels beyond the wood depth: \(message)")
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
                XCTAssertEqual(theme.board(for: scheme).imageStoneShading,
                               (theme == .surroundStudio || theme == .paperBlossoms) ? .clamshellShoulder
                                   : (theme == .frostPine ? .iceEdge : .artwork))
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
