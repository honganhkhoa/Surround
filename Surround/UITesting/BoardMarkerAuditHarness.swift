//
//  BoardMarkerAuditHarness.swift
//  Surround
//
//  Debug-only, offline board-marker fixtures and native SwiftUI image export.
//  The ordinary gallery keeps --surround-board-marker-audit <cell points>.
//  Add --surround-board-marker-export to render the configured audit matrix.
//  Opt in to full board sizes with --surround-board-marker-export-groups board-sizes
//  and e.g. --surround-board-marker-export-sizes 13,14,40. Individual samples
//  are also selectable with --surround-board-marker-sample board-19x9-coordinates.
//

import SwiftUI
import WidgetKit

enum BoardMarkerAuditContract {
    static let launchArgument = "--surround-board-marker-audit"
    static let exportArgument = "--surround-board-marker-export"
    static let panelArgument = "--surround-board-marker-panel"
    static let sampleArgument = "--surround-board-marker-sample"
}

#if DEBUG && MAIN_APP
extension BoardMarkerAuditContract {
    static var exportsImages: Bool {
        SurroundUITestContract.isEnabled && ProcessInfo.processInfo.arguments.contains(exportArgument)
    }

    static var cellSize: CGFloat? {
        guard SurroundUITestContract.isEnabled else { return nil }
        if let value = argumentValue(launchArgument).flatMap(Double.init), value.isFinite, value > 0 {
            return CGFloat(value)
        }
        return exportsImages || argumentValue(panelArgument) != nil || argumentValue(sampleArgument) != nil ? 20 : nil
    }

    fileprivate static func argumentValue(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

private struct MarkerAuditSample: Identifiable {
    let id: String
    let group: String
    let title: String
    let position: BoardPosition
    var variation: Variation? = nil
    var pending: (move: Move, position: BoardPosition)? = nil
    var markups: BoardMarkups = [:]
    var highlights: [[Int]] = []
    var undo: [[Int]] = []
    var coordinates = false
    var removable = false
    var auditState: BoardMarkerAuditState? = nil
    var renderingMode: WidgetRenderingMode = .fullColor
    var renderingModeName = "fullColor"
    /// Points that carry the sample's main mark, for artwork-variant provenance.
    var targets: [[Int]] = []
    var notes = ""

    @MainActor
    func containerSize(for cellSize: CGFloat) -> CGSize {
        let gutter = coordinates ? 1 : 0
        if position.width == position.height {
            let side = cellSize * CGFloat(position.width + gutter)
            return CGSize(width: side, height: side)
        }
        // BoardView uses min(boardGridSize.width, boardGridSize.height) /
        // max(boardWidth, boardHeight), and both coordinate-grid dimensions
        // derive from container.width. A rectangular slot would therefore
        // shrink the requested cell size. Give the unchanged renderer a
        // square slot large enough for its limiting coordinate fraction.
        let width = CGFloat(position.width), height = CGFloat(position.height)
        let coordinateFraction = coordinates ? min(width / (width + 1), height / (height + 1)) : 1
        // Avoid a division roundoff falling one physical pixel below a
        // requested threshold. This increment is far smaller than one pixel.
        let side = (cellSize * max(width, height) / coordinateFraction).nextUp
        return CGSize(width: side, height: side)
    }
}

@MainActor
private enum MarkerAuditFixtures {
    static let boardSize = 7
    static let opening = [[1, 1], [1, 5], [5, 5], [5, 1], [3, 3], [2, 3], [3, 2], [3, 4]]

    /// Stable, one-based IDs shared by exports and native-screen selection.
    static func panels(for selected: [MarkerAuditSample]) -> [(id: String, samples: [MarkerAuditSample])] {
        let groups = selected.map(\.group).reduce(into: [String]()) { groups, group in
            if !groups.contains(group) { groups.append(group) }
        }
        return groups.flatMap { group in
            let members = selected.filter { $0.group == group }
            // Large and rectangular boards retain their actual cell size in a
            // single-sample panel instead of sharing a clipped 7×7 tile.
            if group == "board-sizes" {
                return members.enumerated().map { ("\(group)-\($0.offset + 1)", [$0.element]) }
            }
            return stride(from: 0, to: members.count, by: 4).map { start in
                ("\(group)-\(start / 4 + 1)", Array(members.dropFirst(start).prefix(4)))
            }
        }
    }

    static func play(_ points: [[Int]]) -> BoardPosition {
        var position = BoardPosition(width: boardSize, height: boardSize)
        for point in points {
            // Fixture mistakes should fail the audit, never silently skip a move.
            position = try! position.makeMove(move: .placeStone(point[0], point[1]))
        }
        return position
    }

    static func position(black: [[Int]] = [], white: [[Int]] = [], last: [Int]? = nil) -> BoardPosition {
        let position = BoardPosition(width: boardSize, height: boardSize)
        for point in black { position[point] = .hasStone(.black) }
        for point in white { position[point] = .hasStone(.white) }
        if let last {
            position.lastMove = .placeStone(last[0], last[1])
            if case .hasStone(let color) = position[last] { position.lastMoveColor = color }
        }
        return position
    }

    static func variation(position: BoardPosition, labels: [Int: [Int]]) -> Variation {
        let orderedPoints = labels.keys.sorted().compactMap { labels[$0] }
        var variation = Variation(position: position,
                                  basePosition: BoardPosition(width: boardSize, height: boardSize),
                                  moves: orderedPoints.map { .placeStone($0[0], $0[1]) })
        // The renderer accepts captured move labels and arbitrary move numbers.
        // Injecting its existing model avoids manufacturing 999 game positions.
        variation.nonDuplicatingMoveCoordinatesByLabel = labels
        return variation
    }

    static func chatCoordinates(_ points: [[Int]]) -> [[Int]] {
        points.map { [boardSize - 1 - $0[0], $0[1]] }
    }

    /// One interior point for each stable image variant, spread across the board.
    static let variantPoints: [[Int]] = {
        let preferred = [[1, 1], [1, 5], [5, 1], [5, 5], [1, 3], [3, 1], [3, 5], [5, 3],
                         [2, 2], [2, 4], [4, 2], [4, 4], [3, 3]]
        let candidates = preferred + (1..<6).flatMap { row in (1..<6).map { [row, $0] } }
        return (0..<4).map { variant in
            candidates.first { StoneImages.variantIndex(row: $0[0], column: $0[1], count: 4) == variant }!
        }
    }()

    static let samples: [MarkerAuditSample] = {
        var samples = [MarkerAuditSample]()
        samples.append(.init(id: "last-black", group: "core", title: "Last move · black",
                             position: play(opening + [[4, 3]]), targets: [[4, 3]]))
        samples.append(.init(id: "last-white", group: "core", title: "Last move · white",
                             position: play(opening + [[4, 3], [4, 4]]), targets: [[4, 4]]))
        let blackToPlay = play(opening)
        let blackPending = try! blackToPlay.makeMove(move: .placeStone(4, 3))
        samples.append(.init(id: "pending-black", group: "core", title: "Pending · black",
                             position: blackToPlay, pending: (.placeStone(4, 3), blackPending), targets: [[4, 3]]))
        let whiteToPlay = play(opening + [[4, 3]])
        let whitePending = try! whiteToPlay.makeMove(move: .placeStone(4, 4))
        samples.append(.init(id: "pending-white", group: "core", title: "Pending · white",
                             position: whiteToPlay, pending: (.placeStone(4, 4), whitePending), targets: [[4, 4]]))

        let marked = play([[3, 1], [5, 1], [3, 2], [5, 2], [3, 3], [5, 3], [3, 4], [5, 4], [3, 5], [5, 5]])
        var markups = BoardMarkups()
        let marks = [BoardMarkup(shapes: [.triangle]), BoardMarkup(shapes: [.square]),
                     BoardMarkup(shapes: [.circle]), BoardMarkup(shapes: [.cross]), BoardMarkup(label: "A")]
        for (index, mark) in marks.enumerated() {
            for row in [1, 3, 5] { markups[BoardPoint(row: row, column: index + 1)] = mark }
        }
        samples.append(.init(id: "markup", group: "core", title: "Markup · empty / black / white",
                             position: marked, markups: markups,
                             notes: "The final A shares the last-move point, retaining the original overlap regression."))
        let base = play(opening)
        let line = try! Variation(basePosition: base, moves: [.placeStone(4, 3), .placeStone(4, 4),
                                                             .placeStone(2, 2), .placeStone(4, 2),
                                                             .placeStone(2, 4), .placeStone(1, 3)])
        samples.append(.init(id: "variation", group: "core", title: "Variation · 1–6",
                             position: line.position, variation: line))

        let scored = play([[2, 0], [4, 0], [2, 1], [4, 1], [2, 2], [4, 2], [2, 3], [4, 3],
                           [2, 4], [4, 4], [2, 5], [4, 5], [2, 6], [4, 6], [6, 3], [0, 3]])
        scored.removedStones = [[0, 3], [6, 3], [3, 0], [3, 6]]
        scored.gameScores = GameScores(
            black: PlayerScore(handicap: 0, komi: 0,
                               scoringPositions: Set((0..<2).flatMap { row in (0..<7).map { [row, $0] } }),
                               stones: 0, territory: 0, prisoners: 0, total: 0),
            white: PlayerScore(handicap: 0, komi: 0,
                               scoringPositions: Set((5..<7).flatMap { row in (0..<7).map { [row, $0] } }),
                               stones: 0, territory: 0, prisoners: 0, total: 0))
        samples.append(.init(id: "score", group: "core", title: "Score · dame · dead", position: scored))
        samples.append(.init(id: "chat-undo", group: "core", title: "Chat highlight · undo",
                             position: play(opening), highlights: chatCoordinates([[1, 1], [1, 5], [3, 0]]),
                             undo: [[3, 3], [3, 4]], coordinates: true))

        for (id, title, point, valid) in [
            ("legal-empty", "Legal crosshair · empty", [4, 3], true),
            ("illegal-empty", "Illegal crosshair · empty", [4, 3], false),
            ("illegal-black", "Illegal crosshair · black", [3, 3], false),
            ("illegal-white", "Illegal crosshair · white", [3, 4], false),
        ] {
            samples.append(.init(id: id, group: "interaction", title: title, position: play(opening),
                                 auditState: .init(highlightedRow: point[0], highlightedColumn: point[1], hoverValid: valid),
                                 targets: [point], notes: "Draw-only hover state; gestures and legality are not simulated."))
        }
        let removalBlack = [[1, 1], [1, 3], [1, 5]]
        let removalWhite = [[3, 1], [3, 3], [3, 5]]
        let removalEmpty = [[5, 1], [5, 3], [5, 5]]
        let removalPoints = removalBlack + removalWhite + removalEmpty
        for restoring in [false, true] {
            let board = position(black: removalBlack, white: removalWhite)
            if restoring { board.removedStones = Set(removalPoints) }
            samples.append(.init(id: restoring ? "restore" : "remove", group: "interaction",
                                 title: restoring ? "Restore + · black / white / empty" : "Remove × · black / white / empty",
                                 position: board, removable: true,
                                 auditState: .init(removalPoints: Set(removalPoints)), targets: removalPoints))
        }
        samples.append(.init(id: "removal-crosshair", group: "interaction", title: "Removal crosshair · both colors",
                             position: play(opening), removable: true,
                             auditState: .init(highlightedRow: 3, highlightedColumn: 3,
                                               removalPoints: [[3, 3], [3, 4], [3, 5]]),
                             targets: [[3, 3], [3, 4], [3, 5]]))

        for removed in [false, true] {
            let board = position(black: [[2, 1], [2, 3], [2, 5]], white: [[4, 1], [4, 3], [4, 5]], last: [2, 3])
            if removed { board.removedStones = [[2, 3], [4, 3]] }
            var estimate = Array(repeating: Array(repeating: PointState.empty, count: 7), count: 7)
            for row in [0, 2, 4, 6] {
                for column in 0..<7 { estimate[row][column] = .hasStone(column < 3 ? .black : .white) }
            }
            board.estimatedScores = estimate
            samples.append(.init(id: removed ? "estimate-dead" : "estimate", group: "estimate",
                                 title: removed ? "Estimate · dead stones" : "Estimate · empty / black / white",
                                 position: board, notes: "The last-move ring yields only where an estimate square covers its point."))
        }

        let labels = [1, 9, 10, 99, 100, 999]
        let labelPoints = (0..<6).map { [3, $0] }
        let labelMap = Dictionary(uniqueKeysWithValues: zip(labels, labelPoints))
        for surface in ["black", "white", "empty", "dead-black", "dead-white"] {
            let board = position(black: surface.contains("black") ? labelPoints : [],
                                 white: surface.contains("white") ? labelPoints : [])
            if surface.hasPrefix("dead") { board.removedStones = Set(labelPoints) }
            samples.append(.init(id: "variation-\(surface)", group: "labels", title: "Variation · \(surface) · 1/9/10/99/100/999",
                                 position: board, variation: variation(position: board, labels: labelMap),
                                 targets: labelPoints,
                                 notes: surface == "empty" ? "Captured variation move labels on empty intersections." : ""))
        }
        let labelBoard = position(black: (0..<6).map { [3, $0] }, white: (0..<6).map { [5, $0] })
        var textMarks = BoardMarkups()
        for (column, label) in ["A", "I", "M", "10", "99", "999"].enumerated() {
            for row in [1, 3, 5] { textMarks[.init(row: row, column: column)] = BoardMarkup(label: label) }
        }
        samples.append(.init(id: "markup-label-widths", group: "labels", title: "Markup text · empty / black / white",
                             position: labelBoard, markups: textMarks))

        let combinationBoard = position(black: [[3, 1], [3, 3], [3, 5]], white: [[5, 1], [5, 3], [5, 5]])
        var combined = BoardMarkups()
        for row in [1, 3, 5] {
            combined[.init(row: row, column: 1)] = .init(shapes: [.triangle, .circle])
            combined[.init(row: row, column: 3)] = .init(label: "A", shapes: [.square])
            combined[.init(row: row, column: 5)] = .init(label: "99", shapes: [.triangle, .square, .circle, .cross])
        }
        samples.append(.init(id: "combined-markup", group: "overlap", title: "Imported combinations · shapes + text",
                             position: combinationBoard, markups: combined,
                             notes: "Deliberately dense imported SGF/OGS mark combinations; preserves their semantics."))
        for color: StoneColor in [.black, .white] {
            let point = [3, 3]
            let board = position(black: color == .black ? [point] : [], white: color == .white ? [point] : [], last: point)
            samples.append(.init(id: "last-plus-label-\(color.rawValue)", group: "overlap",
                                 title: "Last move + A · \(color.rawValue)", position: board,
                                 markups: [.init(row: 3, column: 3): .init(label: "A")], targets: [point]))
            samples.append(.init(id: "chat-undo-markup-\(color.rawValue)", group: "overlap",
                                 title: "Chat + undo + square · \(color.rawValue)", position: board,
                                 markups: [.init(row: 3, column: 3): .init(shapes: [.square])],
                                 highlights: chatCoordinates([point, [0, 0]]), undo: [point, [0, 0]], targets: [point, [0, 0]],
                                 notes: "An undo request on empty point must not draw a stone-only undo glyph."))
        }
        let overlapVariationBoard = position(black: [[3, 3]], white: [[3, 4]])
        samples.append(.init(id: "variation-markup", group: "overlap", title: "Variation + markup + chat",
                             position: overlapVariationBoard,
                             variation: variation(position: overlapVariationBoard, labels: [99: [3, 3], 100: [3, 4]]),
                             markups: [.init(row: 3, column: 3): .init(label: "A", shapes: [.circle]),
                                       .init(row: 3, column: 4): .init(shapes: [.triangle])],
                             highlights: chatCoordinates([[3, 3]]), targets: [[3, 3], [3, 4]]))

        for color: StoneColor in [.black, .white] {
            let board = position()
            board.nextToMove = color
            let move = Move.placeStone(3, 3)
            let preview = try! board.makeMove(move: move)
            samples.append(.init(id: "pending-plus-markup-\(color.rawValue)", group: "overlap",
                                 title: "Pending + existing A · \(color.rawValue)", position: board,
                                 pending: (move, preview), markups: [.init(row: 3, column: 3): .init(label: "A")],
                                 targets: [[3, 3]], notes: "Pending confirmation temporarily takes priority over existing markup."))
        }
        let captureBase = position(black: [[2, 3], [3, 2], [4, 3]], white: [[3, 3]])
        let captureMove = Move.placeStone(3, 4)
        let capturePreview = try! captureBase.makeMove(move: captureMove)
        samples.append(.init(id: "pending-capture-markup", group: "overlap", title: "Pending capture · annotation on emptied point",
                             position: captureBase, pending: (captureMove, capturePreview),
                             markups: [.init(row: 3, column: 3): .init(label: "A"),
                                       .init(row: 3, column: 4): .init(shapes: [.triangle])],
                             targets: [[3, 3], [3, 4]],
                             notes: "Captured white point becomes empty and its A must use the board palette; pending point shows the confirmation cross."))
        let undoEstimate = position(black: [[3, 2]], white: [[3, 4]], last: [3, 2])
        var undoEstimateScores = Array(repeating: Array(repeating: PointState.empty, count: 7), count: 7)
        undoEstimateScores[3][2] = .hasStone(.black)
        undoEstimateScores[3][3] = .hasStone(.black)
        undoEstimateScores[3][4] = .hasStone(.white)
        undoEstimate.estimatedScores = undoEstimateScores
        samples.append(.init(id: "estimate-undo-markup", group: "overlap", title: "Estimate + undo + markup · both colors",
                             position: undoEstimate,
                             markups: [.init(row: 3, column: 2): .init(label: "A"),
                                       .init(row: 3, column: 4): .init(shapes: [.square])],
                             undo: [[3, 2], [3, 4]], targets: [[3, 2], [3, 3], [3, 4]],
                             notes: "Undo glyphs take priority over score fill, score contour and markup; adjacent empty estimate stays visible."))

        let corners = [[0, 0], [0, 6], [6, 0], [6, 6]]
        let edges = [[0, 3], [3, 0], [3, 6], [6, 3]]
        var edgeMarks = BoardMarkups()
        for (index, point) in (corners + edges).enumerated() {
            edgeMarks[.init(row: point[0], column: point[1])] = .init(shapes: [BoardMarkShape.allCases[index % 4]])
        }
        samples.append(.init(id: "edge-shapes", group: "edges", title: "Corner + edge shapes · both colors / empty",
                             position: position(black: [corners[0], corners[3], edges[0]], white: [corners[1], corners[2], edges[3]]),
                             markups: edgeMarks, targets: corners + edges))
        for (index, point) in corners.enumerated() {
            let color: StoneColor = index.isMultiple(of: 2) ? .black : .white
            let board = position(black: color == .black ? [point] : [], white: color == .white ? [point] : [], last: point)
            samples.append(.init(id: "corner-last-\(index)", group: "edges", title: "Corner last move · \(color.rawValue)",
                                 position: board, coordinates: index >= 2, targets: [point]))
        }

        // Explicitly cover every image variant beneath each main automatic
        // mark, and every variant beneath each manual shape and text glyph.
        for color: StoneColor in [.black, .white] {
            for (variant, point) in variantPoints.enumerated() {
                let board = position(black: color == .black ? [point] : [], white: color == .white ? [point] : [], last: point)
                samples.append(.init(id: "variant-last-\(color.rawValue)-\(variant)", group: "variants",
                                     title: "Last · \(color.rawValue) · art \(variant)", position: board, targets: [point]))
                samples.append(.init(id: "variant-pending-\(color.rawValue)-\(variant)", group: "variants",
                                     title: "Pending · \(color.rawValue) · art \(variant)",
                                     position: position(), pending: (.placeStone(point[0], point[1]), board), targets: [point]))
            }
            for glyph in ["triangle", "square", "circle", "cross", "A", "999"] {
                let board = position(black: color == .black ? variantPoints : [], white: color == .white ? variantPoints : [])
                let marks = Dictionary(uniqueKeysWithValues: variantPoints.map { point in
                    (BoardPoint(row: point[0], column: point[1]),
                     BoardMarkShape(rawValue: glyph).map { BoardMarkup(shapes: [$0]) } ?? BoardMarkup(label: glyph))
                })
                samples.append(.init(id: "variant-\(glyph)-\(color.rawValue)", group: "variants",
                                     title: "\(glyph) · \(color.rawValue) · art 0/1/2/3", position: board,
                                     markups: marks, targets: variantPoints))
            }
        }

        for (name, mode) in [("accented", WidgetRenderingMode.accented), ("vibrant", .vibrant)] {
            samples.append(.init(id: "widget-\(name)", group: "widget", title: "Widget branch · \(name)",
                                 position: marked, markups: markups, renderingMode: mode, renderingModeName: name,
                                 notes: "Exercises BoardView's widget rendering branch, not the host widget's final system compositing."))
        }
        return samples
    }()

    /// Explicitly selected full-board material/geometry fixtures. Keep these
    /// out of the ordinary marker gallery and default export matrix.
    static let boardSizeSamples: [MarkerAuditSample] = {
        [(9, 9), (13, 13), (19, 19), (25, 25), (9, 19), (19, 9)].flatMap { width, height in
            [false, true].map { coordinates in
                let center = [height / 2, width / 2]
                let white = [2, 2]
                let empty = [height / 2, width / 2 + 2]
                let position = BoardPosition(width: width, height: height)
                position[center] = .hasStone(.black)
                position[[0, 0]] = .hasStone(.black)
                position[white] = .hasStone(.white)
                position[[height - 1, width - 1]] = .hasStone(.white)
                position.lastMove = .placeStone(center[0], center[1])
                position.lastMoveColor = .black
                let markups: BoardMarkups = [
                    BoardPoint(row: white[0], column: white[1]): BoardMarkup(shapes: [.triangle]),
                    BoardPoint(row: empty[0], column: empty[1]): BoardMarkup(shapes: [.square]),
                ]
                return MarkerAuditSample(
                    id: "board-\(width)x\(height)\(coordinates ? "-coordinates" : "")",
                    group: "board-sizes",
                    title: "\(width)×\(height) · coordinates \(coordinates ? "on" : "off")",
                    position: position, markups: markups, coordinates: coordinates,
                    targets: [center, white, empty, [0, 0], [height - 1, width - 1]],
                    notes: "Width × height; centered last-move stone, white triangle, empty-point square and opposite-corner stones check intersection alignment and edge clipping. Native cell size is not scaled to fit.")
            }
        }
    }()

    static var selectableSamples: [MarkerAuditSample] { samples + boardSizeSamples }
}

@MainActor
private struct MarkerAuditSampleView: View {
    let sample: MarkerAuditSample
    let cellSize: CGFloat
    var showsIdentifier = false

    private var board: BoardView {
        var view = BoardView(widgetRenderingMode: sample.renderingMode,
                             boardPosition: sample.position, variation: sample.variation,
                             showsCoordinate: sample.coordinates, stoneRemovable: sample.removable,
                             newMove: .constant(sample.pending?.move), newPosition: .constant(sample.pending?.position),
                             highlightCoordinates: sample.highlights, undoRequestCoordinates: sample.undo,
                             markups: .constant(sample.markups))
        view.markerAuditState = sample.auditState
        return view
    }

    var body: some View {
        let size = sample.containerSize(for: cellSize)
        VStack(alignment: .leading, spacing: 4) {
            Text(sample.title).font(.caption2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if showsIdentifier { Text(sample.id).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary) }
            board.frame(width: size.width, height: size.height)
        }
    }
}

struct BoardMarkerAuditView: View {
    let cellSize: CGFloat
    @AppStorage(SettingKey<String>.gameTheme.name, store: userDefaults)
    private var gameThemeID = SurroundTheme.standard.rawValue
    @State private var exportStarted = false
    @State private var exportStatus = "Preparing export…"

    private var selection: (id: String, samples: [MarkerAuditSample])? {
        if let id = BoardMarkerAuditContract.argumentValue(BoardMarkerAuditContract.sampleArgument) {
            return (id, MarkerAuditFixtures.selectableSamples.filter { $0.id == id })
        }
        if let id = BoardMarkerAuditContract.argumentValue(BoardMarkerAuditContract.panelArgument) {
            return (id, MarkerAuditFixtures.panels(for: MarkerAuditFixtures.selectableSamples).first { $0.id == id }?.samples ?? [])
        }
        return nil
    }

    var body: some View {
        let theme = SurroundTheme.current(storedID: gameThemeID)
        let side = cellSize * CGFloat(MarkerAuditFixtures.boardSize)
        let columns = [GridItem(.adaptive(minimum: side + cellSize, maximum: side + 2 * cellSize), spacing: 12)]
        Group {
            if let selection {
                MarkerAuditCalibrationPanel(theme: theme, samples: selection.samples,
                                            cellSize: cellSize, panelID: selection.id)
            } else {
                ScrollView {
                    if BoardMarkerAuditContract.exportsImages {
                        Text(exportStatus).font(.callout.monospaced()).padding()
                            .accessibilityIdentifier("uitest.boardMarkerExportStatus")
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(MarkerAuditFixtures.samples) { sample in
                            MarkerAuditSampleView(sample: sample, cellSize: cellSize)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(theme.pageBackground)
        .gameDetailTheme(theme)
        .accessibilityIdentifier("uitest.boardMarkerAudit")
        .task {
            guard BoardMarkerAuditContract.exportsImages, !exportStarted else { return }
            exportStarted = true
            await MarkerAuditExporter.run { exportStatus = $0 }
        }
    }
}

/// A normal on-screen SwiftUI view for calibrating exported boards against
/// device screenshots. Never overrides displayScale or scales board content.
@MainActor
private struct MarkerAuditCalibrationPanel: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var scheme
    let theme: SurroundTheme
    let samples: [MarkerAuditSample]
    let cellSize: CGFloat
    let panelID: String

    var body: some View {
        GeometryReader { geometry in
            let boardWidth = samples.map { $0.containerSize(for: cellSize).width }.max() ?? 0
            let boardHeight = samples.map { $0.containerSize(for: cellSize).height }.max() ?? 0
            let columns = samples.count > 1 && geometry.size.width >= boardWidth * 2 + 52 ? 2 : 1
            let tileWidth = max(boardWidth, (geometry.size.width - 32 - CGFloat(columns - 1) * 20) / CGFloat(columns))
            let rows = (samples.count + columns - 1) / columns
            let exceedsScreen = boardWidth > geometry.size.width - 32
                || CGFloat(rows) * (boardHeight + 64) + 80 > geometry.size.height
            VStack(alignment: .leading, spacing: 12) {
                Text("\(theme.rawValue)-\(scheme == .dark ? "dark" : "light") · \(cellSize.formatted()) pt · device \(Int(displayScale))×")
                    .font(.caption.monospaced())
                Text(panelID).font(.caption.weight(.semibold))
                if samples.isEmpty {
                    Text("Unknown audit panel or sample: \(panelID)")
                } else if exceedsScreen {
                    Text("This panel exceeds the screen at native size. Select one sample or use a larger device.")
                        .font(.caption).foregroundStyle(.orange)
                }
                ForEach(0..<rows, id: \.self) { row in
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(Array(samples.dropFirst(row * columns).prefix(columns))) { sample in
                            MarkerAuditSampleView(sample: sample, cellSize: cellSize, showsIdentifier: true)
                                .frame(width: tileWidth, alignment: .topLeading)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityIdentifier("uitest.boardMarkerPanel.\(panelID)")
    }
}

private struct MarkerAuditAppearance {
    let theme: SurroundTheme
    let scheme: ColorScheme
    var id: String { "\(theme.rawValue)-\(scheme == .dark ? "dark" : "light")" }

    static let all: [MarkerAuditAppearance] = SurroundTheme.allCases.flatMap { theme in
        (theme.colorScheme.map { [$0] } ?? [.light, .dark]).map { .init(theme: theme, scheme: $0) }
    }
}

@MainActor
private struct MarkerAuditPanel: View {
    let appearance: MarkerAuditAppearance
    let samples: [MarkerAuditSample]
    let cellSize: CGFloat
    let scale: CGFloat
    let panelID: String

    private var columns: Int { samples.first?.group == "board-sizes" ? 1 : 2 }
    private var tileWidth: CGFloat {
        max(max(200, cellSize * 8), samples.map { $0.containerSize(for: cellSize).width }.max() ?? 0) + 24
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(appearance.id) · \(cellSize.formatted()) pt · \(Int(scale))× · \(panelID)")
                .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 20) {
                ForEach(0..<(samples.count + columns - 1) / columns, id: \.self) { row in
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(Array(samples.dropFirst(row * columns).prefix(columns))) { sample in
                            MarkerAuditSampleView(sample: sample, cellSize: cellSize, showsIdentifier: true)
                                .frame(width: tileWidth, alignment: .topLeading)
                        }
                    }
                }
            }
        }
        .padding(40)
        .frame(width: CGFloat(columns) * tileWidth + CGFloat(columns - 1) * 20 + 80, alignment: .topLeading)
        .background(appearance.theme.pageBackground)
        .environment(\.surroundTheme, appearance.theme)
        .environment(\.boardAppearance, appearance.theme.board(for: appearance.scheme))
        .environment(\.colorScheme, appearance.scheme)
        .environment(\.displayScale, scale)
        .foregroundStyle(appearance.scheme == .dark ? Color.white : Color.black)
    }
}

@MainActor
private enum MarkerAuditExporter {
    @MainActor
    private struct Configuration {
        var sizes: [CGFloat] = [7, 10, 13, 14, 17, 20, 24, 30, 40, 64]
        var scales: [CGFloat] = [2, 3]
        var appearances = MarkerAuditAppearance.all
        var samples = MarkerAuditFixtures.samples

        init() throws {
            func values(_ suffix: String) -> [String]? {
                BoardMarkerAuditContract.argumentValue("--surround-board-marker-export-" + suffix)?
                    .split(separator: ",").map(String.init)
            }
            func numbers(_ suffix: String, allowed: (CGFloat) -> Bool) throws -> [CGFloat]? {
                guard let text = values(suffix) else { return nil }
                let parsed = text.compactMap { Double($0) }.map { CGFloat($0) }
                guard !parsed.isEmpty, parsed.count == text.count,
                      parsed.allSatisfy({ $0.isFinite && allowed($0) }) else {
                    throw ExportError.invalidConfiguration("Invalid \(suffix): \(text.joined(separator: ","))")
                }
                return parsed
            }
            if let sizes = try numbers("sizes", allowed: { $0 >= 4 && $0 <= 128 }) { self.sizes = sizes }
            if let scales = try numbers("scales", allowed: { $0 == 2 || $0 == 3 }) { self.scales = scales }
            if let selected = values("themes") {
                appearances = appearances.filter { selected.contains($0.id) || selected.contains($0.theme.rawValue) }
                guard !appearances.isEmpty else { throw ExportError.invalidConfiguration("No matching themes") }
            }
            if let selected = values("groups") {
                samples = MarkerAuditFixtures.selectableSamples.filter { selected.contains($0.group) }
                guard !samples.isEmpty else { throw ExportError.invalidConfiguration("No matching groups") }
            }
        }
    }

    private struct TargetRecord: Encodable {
        let row: Int
        let column: Int
        let surface: String
        let artworkVariant: Int?
    }
    private struct SampleRecord: Encodable {
        let id: String
        let group: String
        let title: String
        let notes: String
        /// Retained for square-board consumers; absent for rectangular boards.
        let boardSize: Int?
        let boardWidth: Int
        let boardHeight: Int
        let coordinates: Bool
        let renderingMode: String
        let targets: [TargetRecord]
    }
    private struct PanelRecord: Encodable {
        let file: String
        let theme: String
        let appearance: String
        let requestedCellSize: Double
        /// Representative first sample; mixed panels use `sampleGeometries`.
        let actualCellSize: Double
        let displayScale: Double
        let rendererScale: Double
        let pixelWidth: Int
        let pixelHeight: Int
        let sampleIDs: [String]
        let sampleGeometries: [SampleGeometryRecord]
    }
    private struct SampleGeometryRecord: Encodable {
        let sampleID: String
        let containerWidth: Double
        let containerHeight: Double
        let actualCellSize: Double
        /// Point coordinates relative to this sample's board container.
        let faceOriginX: Double
        let faceOriginY: Double
        let faceWidth: Double
        let faceHeight: Double
        let depthThickness: Double
    }
    private struct Manifest: Encodable {
        var schemaVersion = 3
        let runID: String
        let startedAt: String
        var completedAt: String? = nil
        var state = "running"
        var error: String? = nil
        let sizes: [Double]
        let scales: [Double]
        let appearances: [String]
        let samples: [SampleRecord]
        var panels: [PanelRecord] = []
        let limitations = [
            "Representative sizes, not the continuous set of all possible dimensions.",
            "Draw-only interaction state; no claim about gesture behavior or legality validation.",
            "Widget samples exercise renderer branches, not final system widget compositing.",
            "Default marker fixtures are 7×7; full board sizes require the opt-in board-sizes group. Real layouts and window resize require separate native screenshots.",
        ]
    }
    private struct Progress: Encodable {
        let state: String
        let runID: String
        let completedPanels: Int
        let totalPanels: Int
        let currentPanel: String?
        let error: String?
    }
    private struct FailedManifest: Encodable {
        let schemaVersion = 3
        let runID: String
        let state = "error"
        let error: String
    }
    private enum ExportError: LocalizedError {
        case invalidConfiguration(String)
        case rendererFailed(String)
        var errorDescription: String? {
            switch self {
            case .invalidConfiguration(let message): return message
            case .rendererFailed(let panel): return "ImageRenderer returned no PNG for \(panel)"
            }
        }
    }

    static func run(status: @escaping (String) -> Void) async {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BoardMarkerAudit", isDirectory: true)
        let runID = UUID().uuidString.lowercased()
        var manifest: Manifest?
        var total = 0
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            // A full run is thousands of large PNGs. Each export replaces the
            // previous run folders, so repeated audits do not fill the device.
            let existing = try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            for url in existing where UUID(uuidString: url.lastPathComponent) != nil {
                try FileManager.default.removeItem(at: url)
            }
            try write(Progress(state: "preparing", runID: runID, completedPanels: 0, totalPanels: 0,
                               currentPanel: nil, error: nil), to: root.appendingPathComponent("progress.json"))
            // Yield before asset loading/rendering so launch can finish and the
            // visible audit status appears before the first native render.
            await Task.yield()
            let configuration = try Configuration()
            let folder = root.appendingPathComponent(runID, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let panels = MarkerAuditFixtures.panels(for: configuration.samples)
            total = configuration.appearances.count * configuration.sizes.count * configuration.scales.count * panels.count
            manifest = Manifest(runID: runID, startedAt: ISO8601DateFormatter().string(from: Date()),
                                sizes: configuration.sizes.map { Double($0) }, scales: configuration.scales.map { Double($0) },
                                appearances: configuration.appearances.map(\.id),
                                samples: configuration.samples.map(record))
            try write(manifest!, to: root.appendingPathComponent("manifest.json"))
            for appearance in configuration.appearances {
                for size in configuration.sizes {
                    for scale in configuration.scales {
                        for (panelID, samples) in panels {
                            try Task.checkCancellation()
                            let name = "\(appearance.id)-\(number(size))pt-\(Int(scale))x-\(panelID).png"
                            let count = manifest!.panels.count
                            status("Exporting \(count + 1)/\(total)\n\(name)")
                            try write(Progress(state: "rendering", runID: runID, completedPanels: count, totalPanels: total,
                                               currentPanel: name, error: nil), to: root.appendingPathComponent("progress.json"))
                            await Task.yield()
                            let dimensions: (Int, Int) = try autoreleasepool {
                                let renderer = ImageRenderer(content: MarkerAuditPanel(appearance: appearance, samples: samples,
                                                                                      cellSize: size, scale: scale, panelID: panelID))
                                renderer.scale = scale
                                renderer.isOpaque = true
                                guard let image = renderer.uiImage, let cgImage = image.cgImage,
                                      let data = image.pngData() else { throw ExportError.rendererFailed(name) }
                                try data.write(to: folder.appendingPathComponent(name), options: .atomic)
                                return (cgImage.width, cgImage.height)
                            }
                            let sampleGeometries = samples.map {
                                geometryRecord($0, appearance: appearance, cellSize: size, scale: scale)
                            }
                            manifest!.panels.append(PanelRecord(file: "\(runID)/\(name)", theme: appearance.theme.rawValue,
                                                               appearance: appearance.scheme == .dark ? "dark" : "light",
                                                               requestedCellSize: Double(size),
                                                               actualCellSize: sampleGeometries[0].actualCellSize,
                                                               displayScale: Double(scale), rendererScale: Double(scale),
                                                               pixelWidth: dimensions.0, pixelHeight: dimensions.1,
                                                               sampleIDs: samples.map(\.id),
                                                               sampleGeometries: sampleGeometries))
                            try write(Progress(state: "rendering", runID: runID, completedPanels: count + 1, totalPanels: total,
                                               currentPanel: name, error: nil), to: root.appendingPathComponent("progress.json"))
                            await Task.yield()
                        }
                    }
                }
            }
            manifest!.state = "complete"
            manifest!.completedAt = ISO8601DateFormatter().string(from: Date())
            try write(manifest!, to: root.appendingPathComponent("manifest.json"))
            try write(Progress(state: "complete", runID: runID, completedPanels: total, totalPanels: total,
                               currentPanel: nil, error: nil), to: root.appendingPathComponent("progress.json"))
            status("Export complete: \(total) panels\nDocuments/BoardMarkerAudit/manifest.json")
        } catch {
            let message = error.localizedDescription
            if manifest != nil {
                manifest!.state = "error"
                manifest!.error = message
                try? write(manifest!, to: root.appendingPathComponent("manifest.json"))
            } else {
                try? write(FailedManifest(runID: runID, error: message), to: root.appendingPathComponent("manifest.json"))
            }
            try? write(Progress(state: "error", runID: runID, completedPanels: manifest?.panels.count ?? 0,
                                totalPanels: total, currentPanel: nil, error: message), to: root.appendingPathComponent("progress.json"))
            status("Export failed: \(message)")
        }
    }

    private static func number(_ value: CGFloat) -> String {
        String(format: "%.4f", Double(value)).replacingOccurrences(of: ".", with: "p")
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private static func geometryRecord(_ sample: MarkerAuditSample, appearance: MarkerAuditAppearance,
                                       cellSize: CGFloat, scale: CGFloat) -> SampleGeometryRecord {
        let size = sample.containerSize(for: cellSize)
        let geometry = BoardDepthGeometry(
            containerSize: size,
            boardWidth: sample.position.width, boardHeight: sample.position.height, showsCoordinates: sample.coordinates,
            displayScale: scale,
            depth: sample.renderingMode == .fullColor ? appearance.theme.board(for: appearance.scheme).boardDepth : nil)
        return SampleGeometryRecord(sampleID: sample.id,
                                    containerWidth: Double(size.width), containerHeight: Double(size.height),
                                    actualCellSize: Double(geometry.cellSize),
                                    faceOriginX: Double(geometry.faceRect.minX), faceOriginY: Double(geometry.faceRect.minY),
                                    faceWidth: Double(geometry.faceRect.width), faceHeight: Double(geometry.faceRect.height),
                                    depthThickness: Double(geometry.thickness))
    }

    private static func record(_ sample: MarkerAuditSample) -> SampleRecord {
        let position = sample.pending?.position ?? sample.position
        let points = sample.targets.isEmpty ? sample.markups.keys.sorted().map { [$0.row, $0.column] } : sample.targets
        return SampleRecord(id: sample.id, group: sample.group, title: sample.title, notes: sample.notes,
                            boardSize: position.width == position.height ? position.width : nil,
                            boardWidth: position.width, boardHeight: position.height, coordinates: sample.coordinates,
                            renderingMode: sample.renderingModeName, targets: points.map { point in
            let color: String
            let variant: Int?
            if case .hasStone(let stoneColor) = position[point] {
                color = stoneColor.rawValue
                variant = StoneImages.variantIndex(row: point[0], column: point[1], count: 4)
            } else {
                color = "empty"
                variant = nil
            }
            return TargetRecord(row: point[0], column: point[1], surface: color, artworkVariant: variant)
        })
    }
}
#endif
