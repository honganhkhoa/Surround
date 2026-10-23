//
//  AnalyzeTree.swift
//  Surround
//
//  Created by Anh Khoa Hong on 31/05/2021.
//

import SwiftUI

struct AnalyzeTreeSlice: View {
    struct SelectionFrame: Equatable {
        let position: ObjectIdentifier
        let vertical: Bool
        let rect: CGRect
    }

    @Environment(\.surroundTheme) private var theme
    @Environment(\.boardAppearance) private var appearance
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var moveTree: MoveTree
    var lastMoveNumber: Int
    @Binding var selectedPosition: BoardPosition?
    var vertical = false
    var onSelectedBranchFrameChange: ((SelectionFrame) -> Void)?

    /// The selection ring around a 30 pt stone; a keyline widens it a little
    /// so the ring keeps its weight.
    private var selectionDiameter: CGFloat {
        theme.treeMarkKeyline == nil ? 36 : 37
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        vertical ? CGPoint(x: y, y: x) : CGPoint(x: x, y: y)
    }

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
        if vertical {
            HStack(spacing: 0) {
                nodes.padding(.horizontal, 5)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack {
                nodes.padding(.vertical, 5)
                Spacer()
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var nodes: some View {
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
                                    path.move(to: point(15, currentY))
                                    path.addCurve(
                                        to: point(-25, previousY),
                                        control1: point(-10, currentY),
                                        control2: point(-25, previousY)
                                    )
                                }.stroke(Color(.label))
                            }
                            if isConditionalVariation {
                                (theme.conditionalMark ?? .conditionalMoveHighlight)
                                    .frame(width: 40, height: 40)
                                    .cornerRadius(20)
                                    .position(point(15, CGFloat(level) * 40 + 15))
                            }
                            if isSelected(position) {
                                theme.selectionMark
                                    .frame(width: selectionDiameter, height: selectionDiameter)
                                    .cornerRadius(selectionDiameter / 2)
                                    .position(point(15, CGFloat(level) * 40 + 15))
                            }
                            if let keyline = theme.treeMarkKeyline,
                               isConditionalVariation || isSelected(position) {
                                keyline.frame(width: 32, height: 32)
                                    .cornerRadius(16)
                                    .position(point(15, CGFloat(level) * 40 + 15))
                            }
                            
                            Stone(color: lastMoveColor, shadowRadius: 2)
                                .frame(width: 30, height: 30)
                                .position(point(15, CGFloat(level) * 40 + 15))
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
                                // The night page foreground is light, while
                                // this small root icon sits on warm kaya.
                                .foregroundColor(theme == .surroundStudio && colorScheme == .dark
                                    ? appearance.emptyPointMarker : nil)
                                .background(appearance.boardColor.cornerRadius(2))
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
            .frame(width: vertical ? CGFloat(moveTree.maxLevel) * 40 + 32 : 30,
                   height: vertical ? 30 : CGFloat(moveTree.maxLevel) * 40 + 32)
            .onGeometryChange(for: SelectionFrame?.self) { geometry in
                guard onSelectedBranchFrameChange != nil,
                      let selectedPosition,
                      selectedPosition.lastMoveNumber == lastMoveNumber,
                      let level = moveTree.levelByBoardPosition[ObjectIdentifier(selectedPosition)] else {
                    return nil
                }
                let frame = geometry.frame(in: .named("analysisBranchContent"))
                // Include the selection ring, which extends beyond the stone.
                let ring = selectionDiameter
                let overhang = (ring - 30) / 2
                let rect = vertical
                    ? CGRect(x: frame.minX + CGFloat(level) * 40 - overhang, y: 0,
                             width: ring, height: ring)
                    : CGRect(x: 0, y: frame.minY + CGFloat(level) * 40 - overhang,
                             width: ring, height: ring)
                return SelectionFrame(position: ObjectIdentifier(selectedPosition),
                                      vertical: vertical, rect: rect)
            } action: { frame in
                if let frame { onSelectedBranchFrameChange?(frame) }
            }
    }
}

struct BackgroundSlice: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.surroundTheme) private var theme
    var height: CGFloat
    var game: Game
    var lastMoveNumber: Int
    @Binding var selectedPosition: BoardPosition?
    var vertical = false
    
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
                    path.move(to: vertical ? CGPoint(x: 30, y: 15) : CGPoint(x: 15, y: 30))
                    path.addLine(to: vertical ? CGPoint(x: height, y: 15) : CGPoint(x: 15, y: 800))
                }.stroke(theme.treeGuide(scheme: colorScheme))
                if shouldShowBoardThumbnail {
                    if let position = game.positionByLastMoveNumber[lastMoveNumber] {
                        ZStack {
                            if selectedPosition === position {
                                theme.selectionMark
                                    .cornerRadius(3)
                                    .frame(width: 110, height: 110)
                            }
                            BoardView(boardPosition: position)
                                .frame(width: 104, height: 104)
                        }
                        .frame(width: 110, height: 110)
                        .position(vertical ? CGPoint(x: height - 60, y: 15) : CGPoint(x: 15, y: height - 60))
                        .onTapGesture {
                            self.selectedPosition = position
                        }
                    }
                }
            }.frame(width: vertical ? nil : 30, height: vertical ? 30 : nil)
        }
    }
}

struct AnalyzeTreeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var game: Game
    @Binding var selectedPosition: BoardPosition?
    var vertical = false
    @State private var branchScrollPosition = ScrollPosition(edge: .top)
    @State private var branchViewport = CGRect.zero
    @State private var horizontalViewport = CGSize.zero
    @State private var selectedBranchFrame: AnalyzeTreeSlice.SelectionFrame?

    private struct ScrollRequest: Equatable {
        let game: ObjectIdentifier
        let moveNumber: Int
        let lastMoveNumber: Int
        let viewport: CGSize
        let vertical: Bool
        let selection: ObjectIdentifier?
    }

    private func scrollRequest(in viewport: CGSize) -> ScrollRequest {
        ScrollRequest(game: ObjectIdentifier(game),
                      moveNumber: selectedPosition?.lastMoveNumber ?? game.moveTree.largestLastMoveNumber,
                      lastMoveNumber: game.moveTree.largestLastMoveNumber,
                      viewport: viewport, vertical: vertical,
                      selection: selectedPosition.map(ObjectIdentifier.init))
    }

    @MainActor private func restoreSelection(_ request: ScrollRequest, in proxy: ScrollViewProxy) async {
        // Let the lazy rows join this layout. A new selection or viewport
        // cancels the previous task, so an earlier launch-size request cannot
        // overwrite the final centered position.
        await Task.yield()
        guard !Task.isCancelled, request.viewport.width > 0,
              request.viewport.height > 0 else { return }
        proxy.scrollTo(request.moveNumber, anchor: .center)
        revealSelectedBranchIfNeeded()
    }

    private func revealSelectedBranchIfNeeded() {
        guard let selectedPosition, let selectedBranchFrame,
              selectedBranchFrame.position == ObjectIdentifier(selectedPosition),
              selectedBranchFrame.vertical == vertical else { return }
        let frame = selectedBranchFrame.rect
        let viewportLength = vertical ? branchViewport.width : branchViewport.height
        guard viewportLength > 0 else { return }
        let selectedStart = vertical ? frame.minX : frame.minY
        let selectedEnd = vertical ? frame.maxX : frame.maxY
        let viewportStart = vertical ? branchViewport.minX : branchViewport.minY
        let viewportEnd = vertical ? branchViewport.maxX : branchViewport.maxY
        let clearance: CGFloat = 4
        let offset: CGFloat
        if selectedStart < viewportStart + clearance {
            offset = max(0, selectedStart - clearance)
        } else if selectedEnd > viewportEnd - clearance {
            offset = max(0, selectedEnd + clearance - viewportLength)
        } else { return }
        if vertical { branchScrollPosition.scrollTo(x: offset) }
        else { branchScrollPosition.scrollTo(y: offset) }
    }

    private func recordBranchViewport(from old: CGRect, to new: CGRect) {
        branchViewport = new
        // Manual scrolling may leave selection offscreen. Restore only
        // when the viewport changes, or when a new selection is made.
        if old.size != new.size { revealSelectedBranchIfNeeded() }
    }
    
    var body: some View {
        GeometryReader { geometry in
            if vertical {
                verticalTree(in: geometry.size)
            } else {
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
                                                selectedPosition: self.$selectedPosition,
                                                onSelectedBranchFrameChange: { frame in
                                                    selectedBranchFrame = frame
                                                    revealSelectedBranchIfNeeded()
                                                }
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
                            .task(id: scrollRequest(in: horizontalViewport)) {
                                await restoreSelection(scrollRequest(in: horizontalViewport), in: horizontalScrollView)
                            }
                        }
                    }
                    .accessibilityIdentifier(
                        SurroundUITestContract.AccessibilityID.gameAnalyzeTreeScroll
                    )
                    .frame(minHeight: geometry.size.height)
                    .onScrollGeometryChange(for: CGSize.self) { $0.containerSize } action: { _, size in
                        // A parent resize can precede the native scroll view's
                        // layout. Center only after its actual viewport changes.
                        horizontalViewport = size
                    }
                }
                .frame(minHeight: geometry.size.height)
                .coordinateSpace(name: "analysisBranchContent")
            }
            .scrollPosition($branchScrollPosition)
            .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { old, new in
                recordBranchViewport(from: old, to: new)
            }
            .frame(height: geometry.size.height)
            }
        }
        // Slices overlap to connect branches; clip only the complete viewport
        // so scrolling cannot draw or receive taps beneath a side toolbar.
        .clipped()
        .contentShape(Rectangle())
        .background(GameDetailAppearance.panel, ignoresSafeAreaEdges: [])
    }

    private func verticalTree(in size: CGSize) -> some View {
        let contentWidth = max(size.width, CGFloat(game.moveTree.maxLevel) * 40 + 102)
        return ScrollView(.horizontal) {
            ScrollViewReader { scrollView in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(game.moveTree.moveNumberRange), id: \.self) { moveNumber in
                            ZStack(alignment: .leading) {
                                BackgroundSlice(height: contentWidth - 60, game: game,
                                                lastMoveNumber: moveNumber,
                                                selectedPosition: $selectedPosition, vertical: true)
                                    .padding(.leading, 40)
                                HStack(spacing: 10) {
                                    Text(verbatim: "\(moveNumber)")
                                        .font(.body.monospacedDigit())
                                        .fontWeight(moveNumber % 5 == 0 ? .bold : .light)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                        .frame(width: 30, height: 30)
                                    AnalyzeTreeSlice(moveTree: game.moveTree,
                                                     lastMoveNumber: moveNumber,
                                                     selectedPosition: $selectedPosition,
                                                     vertical: true,
                                                     onSelectedBranchFrameChange: { frame in
                                                         selectedBranchFrame = frame
                                                         revealSelectedBranchIfNeeded()
                                                     })
                                }
                            }
                            .frame(height: 30)
                            .zIndex(-Double(moveNumber))
                            .id(moveNumber)
                        }
                        Color.clear.frame(height: 60).id("endOfAnalyzeTree")
                    }
                    .padding(10)
                    .task(id: scrollRequest(in: size)) {
                        await restoreSelection(scrollRequest(in: size), in: scrollView)
                    }
                }
                .frame(width: contentWidth, height: size.height)
                .coordinateSpace(name: "analysisBranchContent")
                .accessibilityIdentifier(SurroundUITestContract.AccessibilityID.gameAnalyzeTreeScroll)
            }
        }
        .scrollPosition($branchScrollPosition)
        .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { old, new in
            recordBranchViewport(from: old, to: new)
        }
        .frame(height: size.height)
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

#Preview("Analysis tree — Vertical conditional", traits: .fixedLayout(width: 320, height: 600)) {
    @Previewable @State var preview = ConditionalAnalyzeTreePreviewState()
    AnalyzeTreeView(game: preview.game, selectedPosition: $preview.selectedPosition, vertical: true)
}
#endif
