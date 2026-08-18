//
//  ConditionalMovesPopover.swift
//  Surround
//

import SwiftUI

extension Color {
    static let conditionalMoveHighlight = Color.orange
}

enum ConditionalMovesPresentationContext: Hashable {
    case home(gameID: Int)
    case gameDetail

    var buttonAccessibilityIdentifier: String {
        switch self {
        case .home(let gameID):
            SurroundUITestContract.AccessibilityID.homeConditionalButton(gameID)
        case .gameDetail:
            SurroundUITestContract.AccessibilityID.gameConditionalButton
        }
    }

    var popoverAccessibilityIdentifier: String {
        switch self {
        case .home(let gameID):
            SurroundUITestContract.AccessibilityID.homeConditionalPopover(gameID)
        case .gameDetail:
            SurroundUITestContract.AccessibilityID.gameConditionalPopover
        }
    }

    func variationAccessibilityIdentifier(
        _ branch: ConditionalMoveBranch
    ) -> String {
        switch self {
        case .home(let gameID):
            SurroundUITestContract.AccessibilityID.homeConditionalVariation(
                gameID,
                branchID: branch.id
            )
        case .gameDetail:
            SurroundUITestContract.AccessibilityID.gameConditionalVariation(
                branch.id
            )
        }
    }
}

enum ConditionalMovesPopoverLayout {
    case compact
    case regular

    var boardSize: CGFloat {
        switch self {
        case .compact:
            160
        case .regular:
            200
        }
    }

    var columnCount: Int {
        switch self {
        case .compact:
            2
        case .regular:
            3
        }
    }
}

struct ConditionalMovesButton: View {
    @ObservedObject var game: Game
    var context: ConditionalMovesPresentationContext
    var onSelect: ((ConditionalMoveBranch) -> Void)?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isPresented = false

    private var popoverLayout: ConditionalMovesPopoverLayout {
        horizontalSizeClass == .compact ? .compact : .regular
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "envelope.and.arrow.trianglehead.branch")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.conditionalMoveHighlight)
        .accessibilityLabel(Text("Conditional moves"))
        .accessibilityIdentifier(context.buttonAccessibilityIdentifier)
        .popover(isPresented: $isPresented) {
            if let onSelect {
                ConditionalMovesPopoverGrid(
                    branches: game.conditionalMoveBranches,
                    context: context,
                    layout: popoverLayout
                ) { branch in
                    isPresented = false
                    onSelect(branch)
                }
            } else {
                ConditionalMovesPopoverGrid(
                    branches: game.conditionalMoveBranches,
                    context: context,
                    layout: popoverLayout
                )
            }
        }
    }
}

struct ConditionalMovesPopoverGrid: View {
    let branches: [ConditionalMoveBranch]
    let context: ConditionalMovesPresentationContext
    let layout: ConditionalMovesPopoverLayout
    var onSelect: ((ConditionalMoveBranch) -> Void)?

    private let spacing: CGFloat = 12

    private var boardSize: CGFloat {
        layout.boardSize
    }

    private var columnCount: Int {
        layout.columnCount
    }

    private var rowCount: Int {
        max(1, Int(ceil(Double(branches.count) / Double(columnCount))))
    }

    private var popoverWidth: CGFloat {
        boardSize * CGFloat(columnCount) + spacing * CGFloat(columnCount + 2)
    }

    private var popoverHeight: CGFloat {
        min(
            boardSize * CGFloat(rowCount) + spacing * CGFloat(rowCount + 2),
            528
        )
    }

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: boardSize, maximum: boardSize),
                spacing: spacing
            ),
        ]
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(Array(branches.enumerated()), id: \.element.id) {
                    index,
                    branch in
                    variationView(
                        branch,
                        index: index,
                        count: branches.count
                    )
                }
            }
            .padding(spacing * 1.5)
        }
        .frame(width: popoverWidth, height: popoverHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Conditional moves"))
        .accessibilityIdentifier(context.popoverAccessibilityIdentifier)
        .presentationCompactAdaptation(.popover)
    }

    @ViewBuilder
    private func variationView(
        _ branch: ConditionalMoveBranch,
        index: Int,
        count: Int
    ) -> some View {
        let label = Text("Conditional variation \(index + 1) of \(count)")
        let board = BoardView(
            boardPosition: branch.position,
            variation: branch.variation
        )
        .frame(width: boardSize, height: boardSize)
        .allowsHitTesting(false)

        if let onSelect {
            Button {
                onSelect(branch)
            } label: {
                ZStack {
                    board
                        .accessibilityHidden(true)
                    Color.clear
                        .contentShape(Rectangle())
                }
                .frame(width: boardSize, height: boardSize)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel(label)
            .accessibilityHint(Text("Show in Analyze mode"))
            .accessibilityIdentifier(
                context.variationAccessibilityIdentifier(branch)
            )
        } else {
            ZStack {
                board
                    .accessibilityHidden(true)
                Color.clear
            }
            .frame(width: boardSize, height: boardSize)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityIdentifier(
                context.variationAccessibilityIdentifier(branch)
            )
        }
    }
}

#if DEBUG && MAIN_APP
extension Game {
    static func conditionalMovesPreviewFixture(
        branchCount: Int = 3
    ) -> Game {
        let game = TestData.Ongoing19x19wBot1
        let basePosition = game.currentPosition
        var paths = [[Move]]()
        var usedOpponentMoves = Set<Move>()

        if branchCount > 0,
           let passedPosition = try? basePosition.makeMove(move: .pass),
           let response = firstPreviewPlacement(from: passedPosition) {
            paths.append([.pass, response])
            usedOpponentMoves.insert(.pass)
        }

        while paths.count < branchCount,
              let opponentMove = firstPreviewPlacement(
                from: basePosition,
                excluding: usedOpponentMoves
              ),
              let opponentPosition = try? basePosition.makeMove(
                move: opponentMove
              ),
              let response = firstPreviewPlacement(from: opponentPosition) {
            paths.append([opponentMove, response])
            usedOpponentMoves.insert(opponentMove)
        }

        let plan = try! ConditionalMovePlan(
            gameID: game.ogsID!,
            ownerID: game.whitePlayer?.id,
            rootMoveNumber: basePosition.lastMoveNumber,
            paths: paths
        )
        precondition(game.setConditionalMovePlan(plan))
        return game
    }

    private static func firstPreviewPlacement(
        from position: BoardPosition,
        excluding excludedMoves: Set<Move> = []
    ) -> Move? {
        for row in 0..<position.board.count {
            for column in 0..<position.board[row].count {
                let move = Move.placeStone(row, column)
                guard !excludedMoves.contains(move),
                      (try? position.makeMove(move: move)) != nil else {
                    continue
                }
                return move
            }
        }
        return nil
    }
}

#Preview("Conditional variations grid") {
    let game = Game.conditionalMovesPreviewFixture()
    ConditionalMovesPopoverGrid(
        branches: game.conditionalMoveBranches,
        context: .gameDetail,
        layout: .regular,
        onSelect: { _ in }
    )
}

#Preview("Conditional variations grid — Scrolling") {
    let game = Game.conditionalMovesPreviewFixture(branchCount: 8)
    ConditionalMovesPopoverGrid(
        branches: game.conditionalMoveBranches,
        context: .gameDetail,
        layout: .compact,
        onSelect: { _ in }
    )
}
#endif
