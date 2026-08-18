//
//  AnalyzeTree.swift
//  Surround
//
//  Created by Anh Khoa Hong on 31/05/2021.
//

import SwiftUI

struct AnalyzeTreeSlice: View {
    @ObservedObject var moveTree: MoveTree
    var lastMoveNumber: Int
    @Binding var selectedPosition: BoardPosition?

    private func accessibilityIdentifier(
        for position: BoardPosition
    ) -> String {
        guard SurroundUITestContract.isEnabled,
              let variation = moveTree.variation(to: position) else {
            return ""
        }
        return SurroundUITestContract.AccessibilityID.gameAnalysisPosition(
            baseMoveNumber: variation.basePosition.lastMoveNumber,
            movePath: variation.moves.map { $0.toOGSString() }
        )
    }

    private func isSelected(_ position: BoardPosition) -> Bool {
        selectedPosition === position
    }
    
    var body: some View {
        VStack {
            ZStack {
                ForEach(Array((moveTree.positionsByLastMoveNumber[lastMoveNumber] ?? []).enumerated()), id: \.0) { _, position in
                    if let position = position {
                        if let lastMoveColor = position.lastMoveColor, let level = moveTree.levelByBoardPosition[ObjectIdentifier(position)] {
                            let isConditionalVariation = moveTree
                                .isConditionalVariationPosition(position)
                            if let previousPosition = position.previousPosition, let previousLevel = moveTree.levelByBoardPosition[ObjectIdentifier(previousPosition)] {
                                let currentY: CGFloat = CGFloat(level) * 40 + 15
                                let previousY: CGFloat = CGFloat(previousLevel) * 40 + 15
                                Path { path in
                                    path.move(to: CGPoint(x: 15, y: currentY))
                                    path.addCurve(
                                        to: CGPoint(x: -25, y: previousY),
                                        control1: CGPoint(x: -10, y: currentY),
                                        control2: CGPoint(x: -25, y: previousY)
                                    )
                                }.stroke(Color(.label))
                            }
                            if isConditionalVariation {
                                Color.conditionalMoveHighlight.frame(width: 40, height: 40)
                                    .cornerRadius(20)
                                    .position(x: 15, y: CGFloat(level) * 40 + 15)
                            }
                            if isSelected(position) {
                                Color(UIColor.systemTeal).frame(width: 36, height: 36)
                                    .cornerRadius(18)
                                    .position(x: 15, y: CGFloat(level) * 40 + 15)
                            }
                            
                            Stone(color: lastMoveColor, shadowRadius: 2)
                                .frame(width: 30, height: 30)
                                .position(x: 15, y: CGFloat(level) * 40 + 15)
                                .onTapGesture {
                                    self.selectedPosition = position
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(
                                    Text("Move \(lastMoveNumber)")
                                )
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAddTraits(
                                    isSelected(position) ? .isSelected : []
                                )
                                .accessibilityValue(
                                    Text("Conditional"),
                                    isEnabled: isConditionalVariation
                                )
                                .accessibilityIdentifier(
                                    accessibilityIdentifier(for: position)
                                )
                                // Recreate the platform accessibility element
                                // after server-confirmed membership changes.
                                .id(isConditionalVariation)
                        } else if lastMoveNumber == 0 {
                            Image(systemName: "squareshape.split.3x3")
//                                .font(.system(size: 30))
                                .background(Color(red: 0.86, green: 0.69, blue: 0.42).cornerRadius(2))
                                .onTapGesture {
                                    self.selectedPosition = position
                                }
                                .position(x: 15, y: 15)
                        }
                    }
//                    else {
//                        Color.gray.frame(width: 30, height: 30)
//                            .position(x: 15, y: 15)
//                    }
                }
            }
            .frame(width: 30, height: CGFloat(moveTree.maxLevel) * 40 + 32)
            .padding(.vertical, 5)
            Spacer()
        }.frame(maxHeight: .infinity)
    }
}

struct BackgroundSlice: View {
    @Environment(\.colorScheme) private var colorScheme
    var height: CGFloat
    var game: Game
    var lastMoveNumber: Int
    @Binding var selectedPosition: BoardPosition?
    
    var shouldShowBoardThumbnail: Bool {
        if height < 180 {
            return false
        }
        var highestLevel = 0
        if let lastPosition = game.moveTree.positionsByLastMoveNumber[lastMoveNumber - 1]?.last, let position = lastPosition {
            highestLevel = max(highestLevel, game.moveTree.levelByBoardPosition[ObjectIdentifier(position)] ?? 0)
        }
        if let lastPosition = game.moveTree.positionsByLastMoveNumber[lastMoveNumber]?.last, let position = lastPosition {
            highestLevel = max(highestLevel, game.moveTree.levelByBoardPosition[ObjectIdentifier(position)] ?? 0)
        }
        if let lastPosition = game.moveTree.positionsByLastMoveNumber[lastMoveNumber + 1]?.last, let position = lastPosition {
            highestLevel = max(highestLevel, game.moveTree.levelByBoardPosition[ObjectIdentifier(position)] ?? 0)
        }
        if CGFloat(highestLevel * 40 + 60 + 120) > height {
            return false
        }
        return true
    }
    
    var shouldShowAxis: Bool {
        return lastMoveNumber > 0 && lastMoveNumber % 5 == 0
    }
    
    var centerX: CGFloat {
        return shouldShowBoardThumbnail ? 55 : 15
    }

    var body: some View {
        if shouldShowAxis {
            ZStack(alignment: .bottom) {
                Path { path in
                    path.move(to: CGPoint(x: 15, y: 30))
                    path.addLine(to: CGPoint(x: 15, y: 800))
                }.stroke(Color(colorScheme == .dark ? .systemGray6 : .systemGray4))
                if shouldShowBoardThumbnail {
                    if let position = game.positionByLastMoveNumber[lastMoveNumber] {
                        ZStack {
                            if selectedPosition === position {
                                Color(.systemTeal)
                                    .cornerRadius(3)
                                    .frame(width: 110, height: 110)
                            }
                            BoardView(boardPosition: position)
                                .frame(width: 104, height: 104)
                        }
                        .frame(width: 110, height: 110)
                        .position(x: 15, y: height - 60)
                        .onTapGesture {
                            self.selectedPosition = position
                        }
                    }
                }
            }.frame(width: 30)
        }
    }
}

struct AnalyzeTreeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var game: Game
    @Binding var selectedPosition: BoardPosition?
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                VStack {
                    ScrollView(.horizontal, showsIndicators: true) {
                        ScrollViewReader { horizontalScrollView in
                            LazyHStack(alignment: .top) {
                                ForEach(Array(self.game.moveTree.moveNumberRange), id: \.self) { lastMoveNumber in
                                    ZStack {
                                        BackgroundSlice(
                                            height: geometry.size.height,
                                            game: game,
                                            lastMoveNumber: lastMoveNumber,
                                            selectedPosition: self.$selectedPosition
                                        )
                                        VStack(spacing: 0) {
                                            Spacer().frame(height: 5)
                                            if lastMoveNumber % 5 == 0 {
                                                Text(verbatim: "\(lastMoveNumber)").font(.body.monospacedDigit()).bold()
                                            } else {
                                                Text(verbatim: "\(lastMoveNumber)").font(.body.monospacedDigit())
                                                    .fontWeight(.light)
                                            }
                                            AnalyzeTreeSlice(
                                                moveTree: self.game.moveTree,
                                                lastMoveNumber: lastMoveNumber,
                                                selectedPosition: self.$selectedPosition
                                            )
                                        }
                                    }
                                    .zIndex(-Double(lastMoveNumber))
                                    .id(lastMoveNumber)
                                }
                                Spacer().frame(width: 60)
                                EmptyView().id("endOfAnalyzeTree")
                            }
                            .padding(.horizontal, 10)
                            .onChange(of: self.selectedPosition?.lastMoveNumber) { _, newLastMoveNumber in
                                DispatchQueue.main.async {
                                    withAnimation {
                                        horizontalScrollView.scrollTo(newLastMoveNumber)
                                    }
                                }
                            }
                            .onAppear {
                                if let lastMoveNumber = self.selectedPosition?.lastMoveNumber {
                                    if lastMoveNumber == self.game.moveTree.largestLastMoveNumber {
                                        horizontalScrollView.scrollTo("endOfAnalyzeTree")
                                    } else {
                                        horizontalScrollView.scrollTo(lastMoveNumber, anchor: .center)
                                    }
                                } else {
                                    horizontalScrollView.scrollTo("endOfAnalyzeTree")
                                }
                            }
                        }
                    }.frame(minHeight: geometry.size.height)
                }.frame(minHeight: geometry.size.height)
            }.frame(height: geometry.size.height)
        }
        .background(Color(colorScheme == .dark ? .systemGray4 : .systemGray6).shadow(radius: 2))
    }
}

#if DEBUG
private struct AnalyzeTreePreviewState {
    let game: Game
    var selectedPosition: BoardPosition?

    init() {
        let game = TestData.Ongoing19x19wBot3
        try! game.makeMove(
            move: .placeStone(1, 1),
            fromAnalyticsPosition: game.positionByLastMoveNumber[7]!
        )
        selectedPosition = try! game.makeMove(
            move: .placeStone(0, 0),
            fromAnalyticsPosition: game.positionByLastMoveNumber[7]!
        )
        try! game.makeMove(
            move: .placeStone(1, 1),
            fromAnalyticsPosition: game.positionByLastMoveNumber[6]!
        )
        try! game.makeMove(
            move: .placeStone(1, 1),
            fromAnalyticsPosition: game.positionByLastMoveNumber[6]!
        )
        let position = try! game.makeMove(
            move: .placeStone(0, 0),
            fromAnalyticsPosition: game.positionByLastMoveNumber[6]!
        )
        try! game.makeMove(move: .placeStone(2, 2), fromAnalyticsPosition: position)
        self.game = game
    }
}

private struct ConditionalAnalyzeTreePreviewState {
    let game: Game
    var selectedPosition: BoardPosition?

    init() {
        let game = Game.conditionalMovesPreviewFixture()
        self.game = game
        selectedPosition = game.conditionalMoveBranches.last?.position
    }
}

#Preview("Analysis tree — Light", traits: .fixedLayout(width: 390, height: 300)) {
    @Previewable @State var preview = AnalyzeTreePreviewState()

    AnalyzeTreeView(
        game: preview.game,
        selectedPosition: $preview.selectedPosition
    )
}

#Preview("Analysis tree — Dark", traits: .fixedLayout(width: 390, height: 300)) {
    @Previewable @State var preview = AnalyzeTreePreviewState()

    AnalyzeTreeView(
        game: preview.game,
        selectedPosition: $preview.selectedPosition
    )
        .colorScheme(.dark)
}

#Preview("Analysis tree — Conditional", traits: .fixedLayout(width: 390, height: 300)) {
    @Previewable @State var preview = ConditionalAnalyzeTreePreviewState()

    AnalyzeTreeView(
        game: preview.game,
        selectedPosition: $preview.selectedPosition
    )
}
#endif
