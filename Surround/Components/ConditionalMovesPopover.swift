//
//  ConditionalMovesPopover.swift
//  Surround
//

import SwiftUI

extension Color {
    static let conditionalMoveHighlight = Color.brown
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

    var popoverTitleAccessibilityIdentifier: String {
        switch self {
        case .home(let gameID):
            SurroundUITestContract.AccessibilityID
                .homeConditionalPopoverTitle(gameID)
        case .gameDetail:
            SurroundUITestContract.AccessibilityID.gameConditionalPopoverTitle
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
    var usesClearGlass = false
    var usesToolbarStyle = false
    /// Home's line under a name: the envelope, then "Conditional moves set".
    var usesHomeLineStyle = false
    var showsHomeLineTitle = true
    /// The envelope's color on a clock chip; the theme's conditional color otherwise.
    var homeIconColor: Color? = nil
    var onSelect: ((ConditionalMoveBranch) -> Void)?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.surroundTheme) private var theme
    @State private var isPresented = false
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 17

    private var popoverLayout: ConditionalMovesPopoverLayout {
        horizontalSizeClass == .compact ? .compact : .regular
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            if usesHomeLineStyle {
                HStack(spacing: 4) {
                    Image(systemName: "envelope.and.arrow.trianglehead.branch")
                        .font(.system(size: 12))
                        .foregroundStyle(homeIconColor ?? theme.conditionalMark ?? .conditionalMoveHighlight)
                    if showsHomeLineTitle {
                        Text(HomeGameNote.conditionalMoves.text)
                            .lineLimit(1)
                            .modifier(HomeSecondaryText())
                    }
                }
                .font(.footnote)
                .frame(minHeight: 24)
                .contentShape(Rectangle())
            } else {
                Image(systemName: "envelope.and.arrow.trianglehead.branch")
                    .font(usesToolbarStyle ? nil : context == .gameDetail ? .system(size: 14)
                          : usesClearGlass ? .system(size: min(iconSize, 24)) : nil)
            }
        }
        .modifier(ConditionalMoveButtonSurface(usesClearGlass: usesClearGlass,
                                              usesToolbarStyle: usesToolbarStyle,
                                              usesHomeLineStyle: usesHomeLineStyle))
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
        .appReviewPresentationBlocked(isPresented)
    }
}

private struct ConditionalMoveButtonSurface: ViewModifier {
    var usesClearGlass: Bool
    var usesToolbarStyle: Bool
    var usesHomeLineStyle = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if usesHomeLineStyle {
            content.buttonStyle(.plain)
        } else if usesToolbarStyle {
            content.buttonStyle(.plain).tint(Color.conditionalMoveHighlight)
                .foregroundStyle(Color.conditionalMoveHighlight)
        } else if usesClearGlass, #available(iOS 26, *), !reduceTransparency {
            content.buttonStyle(.plain).padding(.horizontal, 10).frame(minHeight: 44)
                .glassEffect(.clear.interactive(), in: Capsule())
                .foregroundStyle(Color.conditionalMoveHighlight)
        } else {
            content.buttonStyle(.borderedProminent).controlSize(.small)
                .tint(.conditionalMoveHighlight).foregroundStyle(.white)
        }
    }
}

struct ConditionalMovesPopoverGrid: View {
    let branches: [ConditionalMoveBranch]
    let context: ConditionalMovesPresentationContext
    let layout: ConditionalMovesPopoverLayout
    var onSelect: ((ConditionalMoveBranch) -> Void)?

    private let spacing: CGFloat = 12
    @ScaledMetric(relativeTo: .headline)
    private var titleMinimumHeight: CGFloat = 44

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
            titleMinimumHeight
                + boardSize * CGFloat(rowCount)
                + spacing * CGFloat(rowCount + 2),
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
        VStack(alignment: .leading, spacing: 0) {
            Text(
                "Conditional moves plan",
                comment: "Title above the saved conditional-move variations in the popover."
            )
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, spacing * 1.5)
            .frame(
                maxWidth: .infinity,
                minHeight: titleMinimumHeight,
                alignment: .bottomLeading
            )
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(
                context.popoverTitleAccessibilityIdentifier
            )

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
