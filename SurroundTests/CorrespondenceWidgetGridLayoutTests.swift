//
//  CorrespondenceWidgetGridLayoutTests.swift
//  SurroundTests
//

import XCTest
import WidgetKit

final class CorrespondenceWidgetGridLayoutTests: XCTestCase {
    private struct SelectionGame: Equatable {
        let id: Int
        let isCorrespondence: Bool
        let isUserTurn: Bool
        let timeLeft: TimeInterval
    }

    private let smallSize = CGSize(width: 133, height: 158)
    private let mediumSize = CGSize(width: 313, height: 158)
    private let largeSize = CGSize(width: 313, height: 354)
    private let extraLargeSize = CGSize(width: 689, height: 354)

    func testFamilyCapacities() {
        XCTAssertEqual(
            CorrespondenceWidgetGridLayout.maximumGameCount(
                for: .systemSmall
            ),
            1
        )
        XCTAssertEqual(
            CorrespondenceWidgetGridLayout.maximumGameCount(
                for: .systemMedium
            ),
            2
        )
        XCTAssertEqual(
            CorrespondenceWidgetGridLayout.maximumGameCount(
                for: .systemLarge
            ),
            4
        )
        XCTAssertEqual(
            CorrespondenceWidgetGridLayout.maximumGameCount(
                for: .systemExtraLarge
            ),
            6
        )
    }

    func testSmallMediumAndLargeSparseLayouts() {
        assertLayout(.systemSmall, count: 0, size: smallSize, 1, 1)
        assertLayout(.systemSmall, count: 1, size: smallSize, 1, 1)

        assertLayout(.systemMedium, count: 1, size: mediumSize, 1, 1)
        assertLayout(.systemMedium, count: 2, size: mediumSize, 2, 1)

        assertLayout(.systemLarge, count: 1, size: largeSize, 1, 1)
        assertLayout(.systemLarge, count: 2, size: largeSize, 2, 1)
        assertLayout(.systemLarge, count: 3, size: largeSize, 2, 2)
        assertLayout(.systemLarge, count: 4, size: largeSize, 2, 2)
    }

    func testExtraLargeFiveAndSixGamesUseThreeByTwo() {
        assertLayout(
            .systemExtraLarge,
            count: 5,
            size: extraLargeSize,
            3,
            2
        )
        assertLayout(
            .systemExtraLarge,
            count: 6,
            size: extraLargeSize,
            3,
            2
        )
    }

    func testExtraLargeOneThroughFourMaximizeBoardSize() {
        for count in 1...4 {
            let selected = CorrespondenceWidgetGridLayout.make(
                family: .systemExtraLarge,
                gameCount: count,
                availableSize: extraLargeSize
            )
            let selectedSize = selected.boardSize(in: extraLargeSize)

            for columns in 1...count {
                let candidate = CorrespondenceWidgetGridLayout(
                    columns: columns,
                    rows: Int(ceil(Double(count) / Double(columns)))
                )
                XCTAssertGreaterThanOrEqual(
                    selectedSize + 0.001,
                    candidate.boardSize(in: extraLargeSize),
                    "count \(count), candidate \(columns) columns"
                )
            }
        }
    }

    func testFramesStayInBoundsAndDoNotOverlap() {
        let cases: [(WidgetFamily, CGSize, ClosedRange<Int>)] = [
            (.systemSmall, smallSize, 1...1),
            (.systemMedium, mediumSize, 1...2),
            (.systemLarge, largeSize, 1...4),
            (.systemExtraLarge, extraLargeSize, 1...6),
        ]

        for (family, size, counts) in cases {
            for count in counts {
                let layout = CorrespondenceWidgetGridLayout.make(
                    family: family,
                    gameCount: count,
                    availableSize: size
                )
                let frames = layout.itemFrames(
                    gameCount: count,
                    in: size
                )
                let boardFrames = layout.boardFrames(
                    gameCount: count,
                    in: size
                )
                XCTAssertEqual(frames.count, count)
                XCTAssertEqual(boardFrames.count, count)
                for frame in frames {
                    XCTAssertGreaterThanOrEqual(frame.minX, 0)
                    XCTAssertGreaterThanOrEqual(frame.minY, 0)
                    XCTAssertLessThanOrEqual(frame.maxX, size.width + 0.001)
                    XCTAssertLessThanOrEqual(frame.maxY, size.height + 0.001)
                }
                for first in frames.indices {
                    for second in frames.indices where second > first {
                        XCTAssertFalse(
                            frames[first].intersects(frames[second]),
                            "\(family) count \(count): \(first), \(second)"
                        )
                    }
                }
                for (cellFrame, boardFrame) in zip(frames, boardFrames) {
                    XCTAssertTrue(cellFrame.contains(boardFrame))
                    XCTAssertEqual(boardFrame.width, boardFrame.height)
                    XCTAssertEqual(
                        boardFrame.minX - cellFrame.minX,
                        CorrespondenceWidgetGridLayout.boardChrome / 2,
                        accuracy: 0.001
                    )
                    XCTAssertEqual(
                        boardFrame.minY - cellFrame.minY,
                        CorrespondenceWidgetGridLayout.boardChrome / 2,
                        accuracy: 0.001
                    )
                }
            }
        }
    }

    func testIncompleteRowsAreCentered() {
        for (family, size, count) in [
            (WidgetFamily.systemLarge, largeSize, 3),
            (WidgetFamily.systemExtraLarge, extraLargeSize, 5),
        ] {
            let layout = CorrespondenceWidgetGridLayout.make(
                family: family,
                gameCount: count,
                availableSize: size
            )
            let frames = layout.itemFrames(gameCount: count, in: size)
            let finalRowCount = layout.itemCount(
                inRow: layout.rows - 1,
                gameCount: count
            )
            let finalRow = Array(frames.suffix(finalRowCount))
            guard let firstFrame = finalRow.first,
                  let lastFrame = finalRow.last else {
                return XCTFail("Missing final row frames")
            }
            XCTAssertEqual(
                firstFrame.minX,
                size.width - lastFrame.maxX,
                accuracy: 0.001
            )
        }
    }

    func testSingleBoardFillsAtLeastEightyFivePercent() {
        for (family, size) in [
            (WidgetFamily.systemSmall, smallSize),
            (WidgetFamily.systemMedium, mediumSize),
            (WidgetFamily.systemLarge, largeSize),
            (WidgetFamily.systemExtraLarge, extraLargeSize),
        ] {
            let layout = CorrespondenceWidgetGridLayout.make(
                family: family,
                gameCount: 1,
                availableSize: size
            )
            let limitingUsableDimension = min(
                size.width
                    - CorrespondenceWidgetGridLayout.outerPadding * 2,
                size.height
                    - CorrespondenceWidgetGridLayout.outerPadding * 2
                    - CorrespondenceWidgetGridLayout.timerHeight
            )
            XCTAssertGreaterThanOrEqual(
                layout.boardSize(in: size) / limitingUsableDimension,
                0.85,
                "\(family)"
            )
        }
    }

    func testSelectionFiltersCorrespondenceAndSortsByUrgency() {
        let games = [
            SelectionGame(
                id: 1,
                isCorrespondence: true,
                isUserTurn: false,
                timeLeft: 10
            ),
            SelectionGame(
                id: 2,
                isCorrespondence: false,
                isUserTurn: true,
                timeLeft: 1
            ),
            SelectionGame(
                id: 3,
                isCorrespondence: true,
                isUserTurn: true,
                timeLeft: 20
            ),
            SelectionGame(
                id: 4,
                isCorrespondence: true,
                isUserTurn: true,
                timeLeft: 5
            ),
        ]

        XCTAssertEqual(
            CorrespondenceWidgetContentPolicy.sortedCorrespondenceGames(
                games,
                isCorrespondence: \SelectionGame.isCorrespondence,
                isUserTurn: \SelectionGame.isUserTurn,
                timeLeft: \SelectionGame.timeLeft
            ).map(\.id),
            [4, 3, 1]
        )
    }

    func testRailEmphasisPreservesZeroAndPendingStates() {
        XCTAssertEqual(
            CorrespondenceWidgetContentPolicy.railEmphasis(
                pendingCount: 0
            ),
            .neutral
        )
        XCTAssertEqual(
            CorrespondenceWidgetContentPolicy.railEmphasis(
                pendingCount: 1
            ),
            .pending
        )
    }

    func testPrimaryDestinationUsesActualDisplayedGames() {
        XCTAssertEqual(
            CorrespondenceWidgetContentPolicy.primaryDestination(
                displayedGameIDs: [42],
                isPlaceholder: false
            ),
            .game(42)
        )
        let homeCases: [[Int?]] = [[], [1, 2], [-1]]
        for ids in homeCases {
            XCTAssertEqual(
                CorrespondenceWidgetContentPolicy.primaryDestination(
                    displayedGameIDs: ids,
                    isPlaceholder: false
                ),
                .home
            )
        }
        XCTAssertEqual(
            CorrespondenceWidgetContentPolicy.primaryDestination(
                displayedGameIDs: [42],
                isPlaceholder: true
            ),
            .home
        )
    }

    private func assertLayout(
        _ family: WidgetFamily,
        count: Int,
        size: CGSize,
        _ columns: Int,
        _ rows: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            CorrespondenceWidgetGridLayout.make(
                family: family,
                gameCount: count,
                availableSize: size
            ),
            CorrespondenceWidgetGridLayout(columns: columns, rows: rows),
            file: file,
            line: line
        )
    }
}
