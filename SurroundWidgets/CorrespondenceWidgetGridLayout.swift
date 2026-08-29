//
//  CorrespondenceWidgetGridLayout.swift
//  SurroundWidgets
//

import CoreGraphics
import WidgetKit

enum CorrespondenceWidgetRailEmphasis: Equatable {
    case neutral
    case pending
}

enum CorrespondenceWidgetPrimaryDestination: Equatable {
    case home
    case game(Int)
}

/// Data-independent selection rules for the automatic widget.
struct CorrespondenceWidgetContentPolicy {
    static func sortedCorrespondenceGames<GameValue>(
        _ games: [GameValue],
        isCorrespondence: (GameValue) -> Bool,
        isUserTurn: (GameValue) -> Bool,
        timeLeft: (GameValue) -> TimeInterval
    ) -> [GameValue] {
        games.enumerated()
            .filter { isCorrespondence($0.element) }
            .sorted { first, second in
                let firstIsUserTurn = isUserTurn(first.element)
                let secondIsUserTurn = isUserTurn(second.element)
                if firstIsUserTurn != secondIsUserTurn {
                    return firstIsUserTurn
                }

                let firstTimeLeft = timeLeft(first.element)
                let secondTimeLeft = timeLeft(second.element)
                if firstTimeLeft != secondTimeLeft {
                    return firstTimeLeft < secondTimeLeft
                }
                return first.offset < second.offset
            }
            .map(\.element)
    }

    static func pendingCount<GameValue>(
        in games: [GameValue],
        isUserTurn: (GameValue) -> Bool
    ) -> Int {
        games.reduce(into: 0) { count, game in
            if isUserTurn(game) { count += 1 }
        }
    }

    static func railEmphasis(
        pendingCount: Int
    ) -> CorrespondenceWidgetRailEmphasis {
        pendingCount > 0 ? .pending : .neutral
    }

    static func primaryDestination(
        displayedGameIDs: [Int?],
        isPlaceholder: Bool
    ) -> CorrespondenceWidgetPrimaryDestination {
        guard !isPlaceholder,
              displayedGameIDs.count == 1,
              let gameID = displayedGameIDs[0],
              gameID > 0 else {
            return .home
        }
        return .game(gameID)
    }
}

/// Pure layout metrics shared by the widget renderer and its unit tests.
struct CorrespondenceWidgetGridLayout: Equatable {
    static let turnRailWidth: CGFloat = 25
    static let outerPadding: CGFloat = 6
    static let columnSpacing: CGFloat = 6
    static let rowSpacing: CGFloat = 4
    static let boardChrome: CGFloat = 6
    static let timerHeight: CGFloat = 16

    let columns: Int
    let rows: Int

    static func maximumGameCount(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall:
            return 1
        case .systemMedium:
            return 2
        case .systemLarge:
            return 4
        case .systemExtraLarge:
            return 6
        default:
            return 1
        }
    }

    static func make(
        family: WidgetFamily,
        gameCount: Int,
        availableSize: CGSize
    ) -> Self {
        let count = max(1, min(gameCount, maximumGameCount(for: family)))
        switch family {
        case .systemSmall:
            return .init(columns: 1, rows: 1)
        case .systemMedium:
            return .init(columns: min(count, 2), rows: 1)
        case .systemLarge:
            if count <= 2 {
                // Keep a two-game large widget as one scan-friendly row,
                // matching the requested presentation. A vertical stack can
                // gain a few points of board size on some devices, but changes
                // the intended side-by-side comparison.
                return .init(columns: count, rows: 1)
            }
            return .init(columns: 2, rows: 2)
        case .systemExtraLarge:
            if count >= 5 {
                return .init(columns: 3, rows: 2)
            }
            return bestFittingLayout(
                gameCount: count,
                availableSize: availableSize
            )
        default:
            return .init(columns: 1, rows: 1)
        }
    }

    /// Number of real items in a row. This also makes incomplete-row behavior
    /// directly testable without coupling tests to SwiftUI's layout engine.
    func itemCount(inRow row: Int, gameCount: Int) -> Int {
        guard row >= 0, row < rows, gameCount > 0 else { return 0 }
        let firstIndex = row * columns
        return max(0, min(columns, gameCount - firstIndex))
    }

    /// Expected cell frames for the centered SwiftUI grid. The renderer uses
    /// the same dimensions and spacing; exposing the math here lets tests
    /// verify bounds, overlap, and incomplete-row centering.
    func itemFrames(
        gameCount: Int,
        in availableSize: CGSize
    ) -> [CGRect] {
        let count = max(0, min(gameCount, columns * rows))
        guard count > 0 else { return [] }

        let boardSize = boardSize(in: availableSize)
        let cellSize = CGSize(
            width: boardSize + Self.boardChrome,
            height: boardSize + Self.boardChrome + Self.timerHeight
        )
        let occupiedHeight = cellSize.height * CGFloat(rows)
            + Self.rowSpacing * CGFloat(rows - 1)
        let firstY = (availableSize.height - occupiedHeight) / 2

        return (0..<rows).flatMap { row -> [CGRect] in
            let rowCount = itemCount(inRow: row, gameCount: count)
            guard rowCount > 0 else { return [] }
            let occupiedWidth = cellSize.width * CGFloat(rowCount)
                + Self.columnSpacing * CGFloat(rowCount - 1)
            let firstX = (availableSize.width - occupiedWidth) / 2
            return (0..<rowCount).map { column in
                CGRect(
                    x: firstX
                        + CGFloat(column)
                            * (cellSize.width + Self.columnSpacing),
                    y: firstY
                        + CGFloat(row)
                            * (cellSize.height + Self.rowSpacing),
                    width: cellSize.width,
                    height: cellSize.height
                )
            }
        }
    }

    /// Board-only frames inside each cell. Keeping this derivation beside the
    /// production grid algorithm lets physical widget tests sample the exact
    /// regions rendered by the widget without maintaining parallel geometry.
    func boardFrames(
        gameCount: Int,
        in availableSize: CGSize
    ) -> [CGRect] {
        let boardSize = boardSize(in: availableSize)
        return itemFrames(gameCount: gameCount, in: availableSize).map {
            CGRect(
                x: $0.minX + Self.boardChrome / 2,
                y: $0.minY + Self.boardChrome / 2,
                width: boardSize,
                height: boardSize
            )
        }
    }

    func boardSize(in availableSize: CGSize) -> CGFloat {
        let usableWidth = max(
            0,
            availableSize.width - Self.outerPadding * 2
                - Self.columnSpacing * CGFloat(columns - 1)
        )
        let usableHeight = max(
            0,
            availableSize.height - Self.outerPadding * 2
                - Self.rowSpacing * CGFloat(rows - 1)
        )
        let cellWidth = usableWidth / CGFloat(columns)
        let cellHeight = usableHeight / CGFloat(rows)
        return max(
            1,
            min(
                cellWidth - Self.boardChrome,
                cellHeight - Self.boardChrome - Self.timerHeight
            )
        )
    }

    private static func bestFittingLayout(
        gameCount: Int,
        availableSize: CGSize
    ) -> Self {
        var best = Self(columns: 1, rows: gameCount)
        var bestBoardSize = best.boardSize(in: availableSize)
        guard gameCount > 1 else { return best }

        for columns in 2...gameCount {
            let candidate = Self(
                columns: columns,
                rows: Int(ceil(Double(gameCount) / Double(columns)))
            )
            let candidateBoardSize = candidate.boardSize(in: availableSize)
            if candidateBoardSize > bestBoardSize {
                best = candidate
                bestBoardSize = candidateBoardSize
            }
        }
        return best
    }
}
