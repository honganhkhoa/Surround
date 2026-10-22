//
//  BoardMarkerAuditHarness.swift
//  Surround
//
//  Every board marker in the active Game Detail theme, at one cell size, so
//  readability can be compared across themes and sizes in screenshots. The
//  gallery replaces the app's root; launch with the UI-test argument, a theme
//  (or appearance) and `--surround-board-marker-audit <cell points>`.
//

import SwiftUI

enum BoardMarkerAuditContract {
    static let launchArgument = "--surround-board-marker-audit"
}

#if DEBUG && MAIN_APP
extension BoardMarkerAuditContract {
    /// The cell size in points that follows the argument.
    static var cellSize: CGFloat? {
        guard SurroundUITestContract.isEnabled else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: launchArgument),
              arguments.indices.contains(index + 1),
              let value = Double(arguments[index + 1]), value > 0 else { return nil }
        return CGFloat(value)
    }
}

struct BoardMarkerAuditView: View {
    let cellSize: CGFloat
    @AppStorage(SettingKey<String>.gameTheme.name, store: userDefaults)
    private var gameThemeID = SurroundTheme.standard.rawValue

    private struct Sample {
        let title: String
        let position: BoardPosition
        var variation: Variation? = nil
        var pending: (move: Move, position: BoardPosition)? = nil
        var markups: BoardMarkups = [:]
        var highlights: [[Int]] = []
        var undo: [[Int]] = []
        var coordinates = false
    }

    private static let size = 7

    /// Alternating moves from an empty board.
    private static func play(_ points: [[Int]]) -> BoardPosition {
        var position = BoardPosition(width: size, height: size)
        for point in points {
            position = (try? position.makeMove(move: .placeStone(point[0], point[1]))) ?? position
        }
        return position
    }

    private static let opening = [[1, 1], [1, 5], [5, 5], [5, 1], [3, 3], [2, 3], [3, 2], [3, 4]]

    private static let samples: [Sample] = {
        var samples = [Sample]()
        samples.append(Sample(title: "Last move · black", position: play(opening + [[4, 3]])))
        samples.append(Sample(title: "Last move · white", position: play(opening + [[4, 3], [4, 4]])))
        let blackToPlay = play(opening)
        if let next = try? blackToPlay.makeMove(move: .placeStone(4, 3)) {
            samples.append(Sample(title: "Pending · black", position: blackToPlay,
                                  pending: (.placeStone(4, 3), next)))
        }
        let whiteToPlay = play(opening + [[4, 3]])
        if let next = try? whiteToPlay.makeMove(move: .placeStone(4, 4)) {
            samples.append(Sample(title: "Pending · white", position: whiteToPlay,
                                  pending: (.placeStone(4, 4), next)))
        }
        // Markup on empty points (top row), black stones and white stones.
        let marked = play([[3, 1], [5, 1], [3, 2], [5, 2], [3, 3], [5, 3], [3, 4], [5, 4], [3, 5], [5, 5]])
        var markups = BoardMarkups()
        let marks: [BoardMarkup] = [BoardMarkup(shapes: [.triangle]), BoardMarkup(shapes: [.square]),
                                    BoardMarkup(shapes: [.circle]), BoardMarkup(shapes: [.cross]),
                                    BoardMarkup(label: "A")]
        for (index, mark) in marks.enumerated() {
            for row in [1, 3, 5] { markups[BoardPoint(row: row, column: index + 1)] = mark }
        }
        samples.append(Sample(title: "Markup", position: marked, markups: markups))
        let base = play(opening)
        if let variation = try? Variation(basePosition: base, moves: [.placeStone(4, 3), .placeStone(4, 4),
                                                                      .placeStone(2, 2), .placeStone(4, 2),
                                                                      .placeStone(2, 4), .placeStone(1, 3)]) {
            samples.append(Sample(title: "Variation", position: variation.position, variation: variation))
        }
        // Territory squares, dame, and a dead stone inside each area.
        let scored = play([[2, 0], [4, 0], [2, 1], [4, 1], [2, 2], [4, 2], [2, 3], [4, 3], [2, 4], [4, 4],
                           [2, 5], [4, 5], [2, 6], [4, 6], [6, 3], [0, 3]])
        let blackArea = Set((0..<2).flatMap { row in (0..<size).map { [row, $0] } })
        let whiteArea = Set((5..<size).flatMap { row in (0..<size).map { [row, $0] } })
        scored.removedStones = [[0, 3], [6, 3], [3, 0], [3, 6]]
        scored.gameScores = GameScores(
            black: PlayerScore(handicap: 0, komi: 0, scoringPositions: blackArea,
                               stones: 0, territory: 0, prisoners: 0, total: 0),
            white: PlayerScore(handicap: 0, komi: 0, scoringPositions: whiteArea,
                               stones: 0, territory: 0, prisoners: 0, total: 0)
        )
        samples.append(Sample(title: "Score · dame · dead", position: scored))
        // Chat highlights count rows from the bottom.
        let highlighted = play(opening)
        samples.append(Sample(title: "Chat highlight · undo", position: highlighted,
                              highlights: [[size - 1 - 1, 1], [size - 1 - 1, 5], [size - 1 - 3, 0]],
                              undo: [[3, 3], [3, 4]], coordinates: true))
        return samples
    }()

    var body: some View {
        let theme = SurroundTheme.current(storedID: gameThemeID)
        let side = cellSize * CGFloat(Self.size)
        let columns = [GridItem(.adaptive(minimum: side + cellSize, maximum: side + 2 * cellSize), spacing: 12)]
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(Self.samples.indices, id: \.self) { index in
                    let sample = Self.samples[index]
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sample.title).font(.caption2.weight(.semibold))
                        BoardView(boardPosition: sample.position, variation: sample.variation,
                                  showsCoordinate: sample.coordinates,
                                  newMove: .constant(sample.pending?.move),
                                  newPosition: .constant(sample.pending?.position),
                                  highlightCoordinates: sample.highlights,
                                  undoRequestCoordinates: sample.undo,
                                  markups: .constant(sample.markups))
                            .frame(width: sample.coordinates ? side + cellSize : side,
                                   height: sample.coordinates ? side + cellSize : side)
                    }
                }
            }
            .padding(16)
        }
        .background(theme.pageBackground)
        .gameDetailTheme(theme)
        .accessibilityIdentifier("uitest.boardMarkerAudit")
    }
}
#endif
