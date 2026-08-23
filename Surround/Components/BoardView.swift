//
//  BoardView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/18/20.
//

import SwiftUI
import WidgetKit

func stoneSize(geometry: GeometryProxy, boardSize: Int, displayScale: CGFloat) -> CGFloat {
    let size = min(geometry.size.width, geometry.size.height)
    return CGFloat(
        floor(size / CGFloat(boardSize) * displayScale) / displayScale
    )
}

enum StoneRemovalOption: Int {
    case toggleGroup
    case toggleSinglePoint
}

struct Goban: View {
    @Environment(\.displayScale) private var displayScale
    var geometry: GeometryProxy
    var width: Int
    var height: Int
    var showsCoordinates = false
    var playable = false
    var stoneRemovable = false
    @Binding var highlightedRow: Int
    @Binding var highlightedColumn: Int
    var hoveredPoint: Binding<[Int]?> = .constant(nil)
    var isHoveredPointValid: Bool? = nil
    var selectedPoint: Binding<[Int]?> = .constant(nil)
    #if MAIN_APP
    @State var selectionFeedbackGenerator: UISelectionFeedbackGenerator? = nil
    #endif

    @Setting(.hapticsFeedback) var hapticsFeedbback: Bool
    
    var body: some View {
        let size = stoneSize(geometry: geometry, boardSize: max(width, height), displayScale: displayScale)
        var starPoints = [[CGFloat]]()
        if size > 10 {
            if height == 19 && width == 19 {
                starPoints = [3, 9, 15].flatMap({ x in [3, 9, 15].map({ y in [x, y] })})
            } else if height == 13 && width == 13 {
                starPoints = [[3, 3], [3, 9], [6, 6], [9, 3], [9, 9]]
            } else if height == 9 && width == 9 {
                starPoints = [[2, 2], [2, 6], [4, 4], [6, 2], [6, 6]]
            }
        }
        let highlightColor = stoneRemovable
            ? UIColor.systemTeal
            : (isHoveredPointValid ?? false) ? UIColor.systemGreen : UIColor.systemRed
        let coordinates = "ABCDEFGHJKLMNOPQRSTUVWXYZ".map { String($0) }
        return Group {
            ZStack {
                if showsCoordinates {
                    ForEach(0..<width, id: \.self) { col in
                        Text(verbatim: "\(coordinates[col])").font(.system(size: size > 30 ? size / 1.5 : size))
                            .minimumScaleFactor(0.2)
                            .foregroundColor(.black)
                            .frame(width: size, height: size)
                            .position(x: (CGFloat(col) + 0.5) * size, y: -0.5 * size)
                    }
                    ForEach(0..<height, id: \.self) { row in
                        Text(verbatim: "\(height - row)").font(.system(size: size > 30 ? size / 1.5 : size))
                            .minimumScaleFactor(0.2)
                            .foregroundColor(.black)
                            .frame(width: size, height: size)
                            .position(x: -0.5 * size, y: (CGFloat(row) + 0.5) * size)
                    }
                }
                Path { path in
                    for i in 1..<height-1 {
                        path.move(to: CGPoint(x: size / 2, y: (CGFloat(i) + 0.5) * size))
                        path.addLine(to: CGPoint(x: (CGFloat(width) - 0.5) * size, y:(CGFloat(i) + 0.5) * size))
                    }
                    for i in 1..<width-1 {
                        path.move(to: CGPoint(x: (CGFloat(i) + 0.5) * size, y: size / 2))
                        path.addLine(to: CGPoint(x: (CGFloat(i) + 0.5) * size, y: (CGFloat(height) - 0.5) * size))
                    }
                }
                .stroke(Color.black, lineWidth: size < 10 ? 1 / displayScale : 0.5)
                Path { path in
                    path.move(to: CGPoint(x: size / 2, y: size / 2))
                    path.addLine(to: CGPoint(x: (CGFloat(width) - 0.5) * size, y: size / 2))
                    path.addLine(to: CGPoint(x: (CGFloat(width) - 0.5) * size, y: (CGFloat(height) - 0.5) * size))
                    path.addLine(to: CGPoint(x: size / 2, y: (CGFloat(height) - 0.5) * size))
                    path.closeSubpath()
                }.stroke(Color.black, lineWidth: size < 10 ? 0.5 : 1)
                if starPoints.count > 0 {
                    Path { path in
                        for starPoint in starPoints {
                            let starPointSize: CGFloat = size > 20 ? 6.0 : 4.0
                            let starPointRect = CGRect(x: (starPoint[0] + 0.5) * size - starPointSize / 2, y: (starPoint[1] + 0.5) * size - starPointSize / 2, width: starPointSize, height: starPointSize)
                            path.addEllipse(in: starPointRect)
                        }
                    }.fill(Color.black)
                }
                if highlightedColumn >= 0 && highlightedColumn < width && highlightedRow >= 0 && highlightedRow < height {
                    Path { path in
                        path.move(to: CGPoint(x: size / 2, y: (CGFloat(highlightedRow) + 0.5) * size))
                        path.addLine(to: CGPoint(x: (CGFloat(width) - 0.5) * size, y:(CGFloat(highlightedRow) + 0.5) * size))

                        path.move(to: CGPoint(x: (CGFloat(highlightedColumn) + 0.5) * size, y: size / 2))
                        path.addLine(to: CGPoint(x: (CGFloat(highlightedColumn) + 0.5) * size, y: (CGFloat(height) - 0.5) * size))
                    }
                    .stroke(Color(highlightColor), lineWidth: 1)
                }
            }
        }
        .frame(width: size * CGFloat(width), height: size * CGFloat(height))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged({ value in
                    #if MAIN_APP
                    if self.selectionFeedbackGenerator == nil && self.hapticsFeedbback {
                        self.selectionFeedbackGenerator = SystemPlatformServices.shared
                            .makeSelectionFeedbackGenerator()
                    }
                    #endif
                    selectedPoint.wrappedValue = nil
                    highlightedRow = Int((value.location.y / size - 0.5).rounded())
                    highlightedColumn = Int((value.location.x / size - 0.5).rounded())
                    if highlightedColumn >= 0 && highlightedColumn < width && highlightedRow >= 0 && highlightedRow < height {
                        if hoveredPoint.wrappedValue != [highlightedRow, highlightedColumn] {
                            hoveredPoint.wrappedValue = [highlightedRow, highlightedColumn]
                            #if MAIN_APP
                            self.selectionFeedbackGenerator?.selectionChanged()
                            #endif
                        }
                    } else {
                        hoveredPoint.wrappedValue = nil
                    }
                })
                .onEnded { _ in
                    highlightedRow = -1
                    highlightedColumn = -1
                    if isHoveredPointValid ?? false {
                        if let hoveredPoint = hoveredPoint.wrappedValue {
                            selectedPoint.wrappedValue = hoveredPoint
                            #if MAIN_APP
                            if self.hapticsFeedbback {
                                SystemPlatformServices.shared.playNotificationFeedback(.success)
                            }
                            #endif
                        } else {
                            #if MAIN_APP
                            if self.hapticsFeedbback {
                                SystemPlatformServices.shared.playNotificationFeedback(.warning)
                            }
                            #endif
                        }
                    }
                    hoveredPoint.wrappedValue = nil
                    #if MAIN_APP
                    self.selectionFeedbackGenerator = nil
                    #endif
                }
        )
    }
}

struct VariationNumberings: View {
    var variation: Variation
    var cellSize: CGFloat
    
    var body: some View {
        let labels = Array(variation.nonDuplicatingMoveCoordinatesByLabel.keys)
        
        return ZStack {
            ForEach(labels, id: \.self) { label -> AnyView in
                if let coordinate = variation.nonDuplicatingMoveCoordinatesByLabel[label] {
                    let stoneColor: StoneColor = variation.position[coordinate] == .hasStone(.black) ? .black : .white
                    let labelSize = cellSize >= 14 ? cellSize / 1.5 : cellSize
                    return AnyView(
                        Text(verbatim: "\(label)")
                            .font(.system(size: labelSize))
                            .bold()
                            .foregroundColor(stoneColor == .black ? .white : .black)
                            .minimumScaleFactor(0.2)
                            .frame(width: labelSize, height: labelSize)
                            .position(
                                x: (CGFloat(coordinate[1]) + 0.5) * cellSize,
                                y: (CGFloat(coordinate[0]) + 0.5) * cellSize
                            )
                    )
                } else {
                    return AnyView(EmptyView())
                }
            }
        }
    }
}

struct Stones: View {
    @Environment(\.displayScale) private var displayScale
    @ObservedObject var boardPosition: BoardPosition
    var variation: Variation?
    var geometry: GeometryProxy
    var isLastMovePending = false
    var undoRequestCoordinates: [[Int]] = []

    var body: some View {
        let width = boardPosition.width
        let height = boardPosition.height
        let indicatorMode = BoardStoneIndicatorMode(variation: variation)
                
        let size = stoneSize(geometry: geometry, boardSize: max(width, height), displayScale: displayScale)
        let whiteLivingPath = CGMutablePath()
        let blackLivingPath = CGMutablePath()
        let whiteCapturedPath = CGMutablePath()
        let blackCapturedPath = CGMutablePath()
        let whiteScoreIndicator = CGMutablePath()
        let blackScoreIndicator = CGMutablePath()
        let dameIndicator = CGMutablePath()
        let whiteEstimatedScore = CGMutablePath()
        let blackEstimatedScore = CGMutablePath()

        let drawsShadow = size >= 14
        let shadowOffset: CGFloat = size > 30 ? 2 : 1
        
        let whitePaths = [CGMutablePath(), CGMutablePath(), CGMutablePath(), CGMutablePath()]
        let blackPaths = [CGMutablePath(), CGMutablePath(), CGMutablePath(), CGMutablePath()]

        for row in 0..<height {
            for column in 0..<width {
                if case .hasStone(let stoneColor) = boardPosition[row, column] {
                    let padding = size < 10 ? CGFloat(0.0) : CGFloat(1.0)
                    let stoneRect = CGRect(x: CGFloat(column) * size + padding, y: CGFloat(row) * size + padding, width: size - padding * 2, height: size - padding * 2)
                    if boardPosition.removedStones?.contains([row, column]) ?? false {
                        if stoneColor == .white {
                            whiteCapturedPath.addEllipse(in: stoneRect)
                        } else {
                            blackCapturedPath.addEllipse(in: stoneRect)
                        }
                    } else {
                        if stoneColor == .white {
                            whiteLivingPath.addEllipse(in: stoneRect)
                            
                            // Needs 4 paths to avoid drawing adjacent (orthogonally and diagonally)
                            // stones in the same path.
                            whitePaths[(row % 2) * 2 + (column % 2)].addEllipse(in: stoneRect)
                        } else {
                            blackLivingPath.addEllipse(in: stoneRect)
                            blackPaths[(row % 2) * 2 + (column % 2)].addEllipse(in: stoneRect)
                        }
                    }
                    
                }
                let scoringRectSize = max(size / 3, 2)
                let scoringRectPadding = (size - scoringRectSize) / 2
                let scoringRect = CGRect(
                    x: CGFloat(column) * size + scoringRectPadding,
                    y: CGFloat(row) * size + scoringRectPadding,
                    width: scoringRectSize,
                    height: scoringRectSize)
                if let scores = boardPosition.gameScores {
                    let isRemoved = boardPosition.removedStones?.contains([row, column]) ?? false
                    if boardPosition[row, column] == .empty && isRemoved {
                        dameIndicator.addRect(scoringRect)
                    } else {
                        if scores.black.scoringPositions.contains([row, column]) {
                            blackScoreIndicator.addRect(scoringRect)
                        } else if scores.white.scoringPositions.contains([row, column]) {
                            whiteScoreIndicator.addRect(scoringRect)
                        }
                    }
                }
                if let estimatedScores = boardPosition.estimatedScores {
                    if case .hasStone(let color) = estimatedScores[row][column] {
                        if color == .black {
                            blackEstimatedScore.addRect(scoringRect)
                        } else {
                            whiteEstimatedScore.addRect(scoringRect)
                        }
                    }
                }
            }
        }
        
        let lastMoveIndicatorWidth: CGFloat = size >= 20 ? 2 : (size > 10 ? 1 : 0.5)
        let undoMarkerCoordinates = undoRequestCoordinates.filter { coordinate in
            guard coordinate.count == 2 else {
                return false
            }
            let row = coordinate[0]
            let column = coordinate[1]
            guard row >= 0, row < height, column >= 0, column < width else {
                return false
            }
            if case .hasStone = boardPosition[row, column] {
                return true
            }
            return false
        }
        
        return ZStack {
            if drawsShadow {
                ForEach(whitePaths, id:\.self) { path in
                    Path(path).fill(
                        Color.white
                            .shadow(.inner(color: Color(red: 0.8, green: 0.8, blue: 0.8), radius: size / 4, x: -size / 2.5, y: -size / 2.5))
                    ).shadow(radius: 2, x: shadowOffset, y: shadowOffset)
                }

                ForEach(blackPaths, id:\.self) { path in
                    Path(path).fill(
                        Color(red: 0.6, green: 0.6, blue: 0.6)
                            .shadow(.inner(color: Color.black, radius: size / 4, x: -size / 2.5, y: -size / 2.5))
                    ).shadow(radius: 2, x: shadowOffset, y: shadowOffset)
                }
            } else {
                Path(whiteLivingPath).fill(Color.white)
                Path(whiteLivingPath).stroke(Color.gray, lineWidth: 0.5)
                Path(blackLivingPath).fill(Color.black)
            }
            
            if boardPosition.removedStones != nil {
                Path(whiteCapturedPath).fill(Color.white).opacity(0.5)
                Path(whiteCapturedPath).stroke(Color.gray)
                Path(blackCapturedPath).fill(Color.black).opacity(0.5)
            }

            if indicatorMode == .variationNumberings, let variation {
                VariationNumberings(variation: variation, cellSize: size)
            } else if case .placeStone(let lastRow, let lastColumn) = boardPosition.lastMove {
                if case .hasStone(let lastColor) = boardPosition[lastRow, lastColumn] {
                    if boardPosition.estimatedScores == nil
                        && !undoMarkerCoordinates.contains([lastRow, lastColumn]) {
                        if isLastMovePending {
                            Path { path in
                                let centerX = CGFloat(lastColumn) * size + size / 2
                                let centerY = CGFloat(lastRow) * size + size / 2
                                path.move(to: CGPoint(x: centerX - size / 4, y: centerY))
                                path.addLine(to: CGPoint(x: centerX + size / 4, y: centerY))
                                path.move(to: CGPoint(x: centerX, y: centerY - size / 4))
                                path.addLine(to: CGPoint(x: centerX, y: centerY + size / 4))
                            }
                            .stroke(lastColor == .white ? Color.gray : Color.white, lineWidth: lastMoveIndicatorWidth)
                        } else {
                            Path { path in
                                path.addEllipse(in: CGRect(
                                                    x: CGFloat(lastColumn) * size + size / 4,
                                                    y: CGFloat(lastRow) * size + size / 4,
                                                    width: size / 2,
                                                    height: size / 2))
                            }
                            .stroke(lastColor == .white ? Color.gray : Color.white, lineWidth: lastMoveIndicatorWidth)
                        }
                    }
                }
            }

            if indicatorMode == .positionIndicators {
                ForEach(Array(undoMarkerCoordinates.enumerated()), id: \.offset) { _, coordinate in
                    let row = coordinate[0]
                    let column = coordinate[1]
                    if case .hasStone(let stoneColor) = boardPosition[row, column] {
                        Text(verbatim: "↶")
                            .font(.system(size: size * 0.65, weight: .bold))
                            .foregroundColor(stoneColor == .black ? .white : .black)
                            .minimumScaleFactor(0.2)
                            .frame(width: size, height: size)
                            .position(
                                x: (CGFloat(column) + 0.5) * size,
                                y: (CGFloat(row) + 0.5) * size
                            )
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
            
            if boardPosition.gameScores != nil {
                Path(dameIndicator).stroke(Color(UIColor.systemIndigo), lineWidth: lastMoveIndicatorWidth)
                Path(whiteScoreIndicator).fill(Color.white)
                Path(whiteScoreIndicator).stroke(Color.gray, lineWidth: 0.5)
                Path(blackScoreIndicator).fill(Color.black)
                Path(blackScoreIndicator).stroke(Color.gray, lineWidth: 0.5)
            }

            if boardPosition.estimatedScores != nil {
                Path(whiteEstimatedScore).fill(Color.white)
                Path(whiteEstimatedScore).stroke(Color.gray, lineWidth: 0.5)
                Path(blackEstimatedScore).fill(Color.black)
                Path(blackEstimatedScore).stroke(Color.gray, lineWidth: 0.5)
            }
        }
        .frame(width: size * CGFloat(width), height: size * CGFloat(height))
    }
}

struct StoneRemovalOverlay: View {
    @Environment(\.displayScale) private var displayScale
    @ObservedObject var boardPosition: BoardPosition
    var stoneRemovalOption = StoneRemovalOption.toggleGroup
    var geometry: GeometryProxy
    @Binding var highlightedRow: Int
    @Binding var highlightedColumn: Int
    @State var hoveredGroup = Set<[Int]>()
    var stoneRemovalSelectedPoints: Binding<Set<[Int]>> = .constant(Set<[Int]>())

    var body: some View {
        let width = boardPosition.width
        let height = boardPosition.height
        let size = stoneSize(geometry: geometry, boardSize: max(width, height), displayScale: displayScale)

        let toBeRemovedPath = CGMutablePath()
        let toBeAddedPath = CGMutablePath()
        
        for point in hoveredGroup {
            let row = point[0]
            let column = point[1]
            
            let indicatorRectSize = max(size / 2, 3)
            let indicatorRectPadding = (size - indicatorRectSize) / 2
            let indicatorRect = CGRect(
                x: CGFloat(column) * size + indicatorRectPadding,
                y: CGFloat(row) * size + indicatorRectPadding,
                width: indicatorRectSize,
                height: indicatorRectSize)
            
            if boardPosition.removedStones?.contains([row, column]) ?? false {
                toBeAddedPath.move(to: CGPoint(x: indicatorRect.midX, y: indicatorRect.minY))
                toBeAddedPath.addLine(to: CGPoint(x: indicatorRect.midX, y: indicatorRect.maxY))
                toBeAddedPath.move(to: CGPoint(x: indicatorRect.minX, y: indicatorRect.midY))
                toBeAddedPath.addLine(to: CGPoint(x: indicatorRect.maxX, y: indicatorRect.midY))
            } else {
                toBeRemovedPath.move(to: CGPoint(x: indicatorRect.minX, y: indicatorRect.maxY))
                toBeRemovedPath.addLine(to: CGPoint(x: indicatorRect.maxX, y: indicatorRect.minY))
                toBeRemovedPath.move(to: CGPoint(x: indicatorRect.minX, y: indicatorRect.minY))
                toBeRemovedPath.addLine(to: CGPoint(x: indicatorRect.maxX, y: indicatorRect.maxY))
            }
        }
        let indicatorWidth: CGFloat = size >= 20 ? 2.5 : (size > 10 ? 2 : 1)
        
        return ZStack {
            Color.clear
            Path(toBeRemovedPath).stroke(Color(UIColor.systemRed), lineWidth: indicatorWidth)
            Path(toBeAddedPath).stroke(Color(UIColor.systemGreen), lineWidth: indicatorWidth)
        }
        .frame(width: size * CGFloat(width), height: size * CGFloat(height))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged({ value in
                    let newRow = Int((value.location.y / size - 0.5).rounded())
                    let newColumn = Int((value.location.x / size - 0.5).rounded())
                    
                    if newColumn >= 0 && newColumn < width && newRow >= 0 && newRow < height {
                        if newRow != highlightedRow || newColumn != highlightedColumn {
                            highlightedRow = newRow
                            highlightedColumn = newColumn
                            if !hoveredGroup.contains([newRow, newColumn]) {
                                if stoneRemovalOption == .toggleGroup {
                                    hoveredGroup = self.boardPosition.groupForStoneRemoval(atRow: newRow, column: newColumn)
                                } else {
                                    hoveredGroup = Set<[Int]>([[newRow, newColumn]])
                                }
                            }
                        }
                    } else {
                        highlightedRow = -1
                        highlightedColumn = -1
                        hoveredGroup.removeAll()
                    }
                })
                .onEnded { _ in
                    stoneRemovalSelectedPoints.wrappedValue = hoveredGroup
                    highlightedRow = -1
                    highlightedColumn = -1
                }
        )
        .onChange(of: stoneRemovalSelectedPoints.wrappedValue) { _, newSelectedPoints in
            if newSelectedPoints.count == 0 {
                hoveredGroup.removeAll()
            }
        }
    }
}

struct CoordinateHighlightOverlay: View {
    @Environment(\.displayScale) private var displayScale
    @ObservedObject var boardPosition: BoardPosition
    var geometry: GeometryProxy
    var highlightCoordinates: [[Int]]

    var body: some View {
        let width = boardPosition.width
        let height = boardPosition.height
                
        let size = stoneSize(geometry: geometry, boardSize: max(width, height), displayScale: displayScale)
        let highlightedCoordinatesPath = CGMutablePath()
        let highlightWidth: CGFloat = size >= 20 ? 3 : (size > 10 ? 2 : 1)

        for coordinate in highlightCoordinates {
            let row = boardPosition.height - coordinate[0] - 1
            let column = coordinate[1]

            let highlightRectSize = size / 1.5
            let highlightRectPadding = (size - highlightRectSize) / 2
            let highlightRect = CGRect(
                x: CGFloat(column) * size + highlightRectPadding,
                y: CGFloat(row) * size + highlightRectPadding,
                width: highlightRectSize,
                height: highlightRectSize)
            
            highlightedCoordinatesPath.move(to: CGPoint(x: highlightRect.midX, y: highlightRect.minY))
            highlightedCoordinatesPath.addLine(to: CGPoint(x: highlightRect.midX - highlightRect.width * 0.433, y: highlightRect.maxY - highlightRect.height / 4))
            highlightedCoordinatesPath.addLine(to: CGPoint(x: highlightRect.midX + highlightRect.width * 0.433, y: highlightRect.maxY - highlightRect.height / 4))
            highlightedCoordinatesPath.addLine(to: CGPoint(x: highlightRect.midX, y: highlightRect.minY))
        }
        
        return ZStack {
            Path(highlightedCoordinatesPath)
                .stroke(Color(.systemBlue), lineWidth: highlightWidth)
        }.frame(width: size * CGFloat(width), height: size * CGFloat(height))
    }
}

struct BoardMarkupOverlay: View {
    @Environment(\.displayScale) private var displayScale
    @ObservedObject var boardPosition: BoardPosition
    var markups: BoardMarkups
    var geometry: GeometryProxy
    var widgetRenderingMode: WidgetRenderingMode

    var body: some View {
        let size = stoneSize(
            geometry: geometry,
            boardSize: max(boardPosition.width, boardPosition.height),
            displayScale: displayScale
        )

        ZStack {
            ForEach(markups.keys.sorted(), id: \.self) { point in
                if point.row >= 0,
                   point.row < boardPosition.height,
                   point.column >= 0,
                   point.column < boardPosition.width,
                   let markup = markups[point] {
                    let foreground = markerColor(at: point)
                    ZStack {
                        if boardPosition[point.row, point.column] == .empty {
                            Circle()
                                .fill(emptyPointBackground)
                                .frame(width: size * 0.62, height: size * 0.62)
                        }
                        ForEach(BoardMarkShape.allCases, id: \.self) { shape in
                            if markup.shapes.contains(shape) {
                                BoardMarkShapeView(shape: shape)
                                    .stroke(
                                        foreground,
                                        style: StrokeStyle(
                                            lineWidth: max(1 / displayScale, size * 0.09),
                                            lineCap: .round,
                                            lineJoin: .round
                                        )
                                    )
                                    .frame(width: size * 0.58, height: size * 0.58)
                            }
                        }
                        if let label = markup.label {
                            Text(verbatim: label)
                                .font(.system(size: size * 0.55, weight: .bold))
                                .minimumScaleFactor(0.35)
                                .foregroundStyle(foreground)
                                .frame(width: size * 0.75, height: size * 0.75)
                        }
                    }
                    .position(
                        x: (CGFloat(point.column) + 0.5) * size,
                        y: (CGFloat(point.row) + 0.5) * size
                    )
                }
            }
        }
        .frame(
            width: size * CGFloat(boardPosition.width),
            height: size * CGFloat(boardPosition.height)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var emptyPointBackground: Color {
        widgetRenderingMode == .fullColor
            ? Color(red: 0.86, green: 0.69, blue: 0.42)
            : Color.white.opacity(0.8)
    }

    private func markerColor(at point: BoardPoint) -> Color {
        if boardPosition[point.row, point.column] == .hasStone(.black) {
            return .white
        }
        return .black
    }
}

private struct BoardMarkShapeView: Shape {
    let shape: BoardMarkShape

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch shape {
        case .triangle:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        case .square:
            path.addRect(rect)
        case .circle:
            path.addEllipse(in: rect)
        case .cross:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        return path
    }
}

private struct BoardMarkupEditingOverlay: View {
    private enum GestureMode {
        case paint
        case clear
    }

    @Environment(\.displayScale) private var displayScale
    @ObservedObject var boardPosition: BoardPosition
    @Binding var markups: BoardMarkups
    @Binding var tool: AnalyzeBoardTool
    var geometry: GeometryProxy
    @State private var visitedPoints = Set<BoardPoint>()
    @State private var gestureMode: GestureMode?
    #if MAIN_APP
    @State private var selectionFeedbackGenerator: UISelectionFeedbackGenerator?
    #endif
    @Setting(.hapticsFeedback) private var hapticsFeedback: Bool

    var body: some View {
        let size = stoneSize(
            geometry: geometry,
            boardSize: max(boardPosition.width, boardPosition.height),
            displayScale: displayScale
        )

        Color.clear
            .frame(
                width: size * CGFloat(boardPosition.width),
                height: size * CGFloat(boardPosition.height)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        editPoint(at: value.location, cellSize: size)
                    }
                    .onEnded { _ in
                        #if MAIN_APP
                        if !visitedPoints.isEmpty && hapticsFeedback {
                            SystemPlatformServices.shared
                                .playNotificationFeedback(.success)
                        }
                        selectionFeedbackGenerator = nil
                        #endif
                        visitedPoints.removeAll()
                        gestureMode = nil
                    }
            )
    }

    private func editPoint(at location: CGPoint, cellSize: CGFloat) {
        let row = Int((location.y / cellSize - 0.5).rounded())
        let column = Int((location.x / cellSize - 0.5).rounded())
        guard row >= 0,
              row < boardPosition.height,
              column >= 0,
              column < boardPosition.width else {
            return
        }

        let point = BoardPoint(row: row, column: column)
        guard visitedPoints.insert(point).inserted else {
            return
        }
        if gestureMode == nil {
            gestureMode = tool == .eraser || tool.matches(markups[point])
                ? .clear
                : .paint
        }

        var updatedMarkups = markups
        switch gestureMode {
        case .clear:
            updatedMarkups[point] = nil
        case .paint:
            updatedMarkups.paint(tool, at: point)
        case nil:
            break
        }
        markups = updatedMarkups

        #if MAIN_APP
        if selectionFeedbackGenerator == nil && hapticsFeedback {
            selectionFeedbackGenerator = SystemPlatformServices.shared
                .makeSelectionFeedbackGenerator()
        }
        selectionFeedbackGenerator?.selectionChanged()
        #endif
    }
}

struct BoardView: View {
    var widgetRenderingMode: WidgetRenderingMode = .fullColor
    @ObservedObject var boardPosition: BoardPosition
    var variation: Variation?
    var showsCoordinate = false
    var playable = false
    var stoneRemovable = false
    var stoneRemovalOption = StoneRemovalOption.toggleGroup
    var newMove: Binding<Move?> = .constant(nil)
    var newPosition: Binding<BoardPosition?> = .constant(nil)
    var allowsSelfCapture: Bool = false
    @State var hoveredPoint: [Int]? = nil
    @State var isHoveredPointValid: Bool? = nil
    @State var selectedPoint: [Int]? = nil
    @State var highlightedRow = -1
    @State var highlightedColumn = -1
    var stoneRemovalSelectedPoints: Binding<Set<[Int]>> = .constant(Set<[Int]>())
    var cornerRadius: CGFloat = 0.0
    var highlightCoordinates: [[Int]] = []
    var undoRequestCoordinates: [[Int]] = []
    var boardTool: Binding<AnalyzeBoardTool> = .constant(.moves)
    var markups: Binding<BoardMarkups> = .constant([:])
    
    var gobanAndStones: some View {
        let displayedPosition = (newMove.wrappedValue != nil && newPosition.wrappedValue != nil) ?
            newPosition.wrappedValue! : boardPosition
        return GeometryReader { boardGeometry in
            ZStack(alignment: .center) {
                Goban(
                    geometry: boardGeometry,
                    width: boardPosition.width,
                    height: boardPosition.height,
                    showsCoordinates: showsCoordinate,
                    playable: playable,
                    stoneRemovable: stoneRemovable,
                    highlightedRow: $highlightedRow,
                    highlightedColumn: $highlightedColumn,
                    hoveredPoint: $hoveredPoint,
                    isHoveredPointValid: isHoveredPointValid,
                    selectedPoint: $selectedPoint
                )
                .allowsHitTesting(
                    playable
                        && boardTool.wrappedValue == .moves
                        && displayedPosition.estimatedScores == nil
                )
                .onChange(of: hoveredPoint) { _, value in
                    isHoveredPointValid = nil
                    if let hoveredPoint = hoveredPoint {
                        do {
                            newPosition.wrappedValue = try boardPosition.makeMove(move: .placeStone(hoveredPoint[0], hoveredPoint[1]), allowsSelfCapture: allowsSelfCapture)
                            isHoveredPointValid = true
                        } catch {
                            isHoveredPointValid = false
                        }
                    }
                }
                .onChange(of: selectedPoint) { _, value in
                    if let selectedPoint = value {
                        newMove.wrappedValue = .placeStone(selectedPoint[0], selectedPoint[1])
                    } else {
                        newMove.wrappedValue = nil
                    }
                }
                Stones(
                    boardPosition: displayedPosition,
                    variation: variation,
                    geometry: boardGeometry,
                    isLastMovePending: newMove.wrappedValue != nil,
                    undoRequestCoordinates: undoRequestCoordinates
                )
                BoardMarkupOverlay(
                    boardPosition: boardPosition,
                    markups: markups.wrappedValue,
                    geometry: boardGeometry,
                    widgetRenderingMode: widgetRenderingMode
                )
                CoordinateHighlightOverlay(
                    boardPosition: boardPosition,
                    geometry: boardGeometry,
                    highlightCoordinates: highlightCoordinates
                )
                if playable && boardTool.wrappedValue != .moves {
                    BoardMarkupEditingOverlay(
                        boardPosition: boardPosition,
                        markups: markups,
                        tool: boardTool,
                        geometry: boardGeometry
                    )
                }
                if stoneRemovable {
                    StoneRemovalOverlay(
                        boardPosition: boardPosition,
                        stoneRemovalOption: stoneRemovalOption,
                        geometry: boardGeometry,
                        highlightedRow: $highlightedRow,
                        highlightedColumn: $highlightedColumn,
                        stoneRemovalSelectedPoints: stoneRemovalSelectedPoints
                    )
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).aspectRatio(1, contentMode: .fit)
        }
    }
    
    var body: some View {
        let width: CGFloat = CGFloat(boardPosition.width)
        let height: CGFloat = CGFloat(boardPosition.height)
        return GeometryReader { geometry in
            ZStack(alignment: .center) {
                if widgetRenderingMode == .fullColor {
                    Color(red: 0.86, green: 0.69, blue: 0.42).cornerRadius(cornerRadius).shadow(radius: 2)
                } else {
                    Color.white.cornerRadius(cornerRadius).opacity(0.5)
                }
                gobanAndStones
                    .frame(
                        width: showsCoordinate ? geometry.size.width * width / (width + 1) : geometry.size.width,
                        height: showsCoordinate ? geometry.size.width * height / (height + 1) : geometry.size.height
                    )
                    .offset(
                        x: showsCoordinate ? geometry.size.width / (width + 1) / 2 : 0,
                        y: showsCoordinate ? geometry.size.height / (height + 1) / 2 : 0
                    )
            }
        }
        .onChange(of: boardTool.wrappedValue) { _, _ in
            hoveredPoint = nil
            selectedPoint = nil
            isHoveredPointValid = nil
            newMove.wrappedValue = nil
            newPosition.wrappedValue = nil
        }
    }
}

#if DEBUG
#Preview("Analysis variation", traits: .fixedLayout(width: 375, height: 375)) {
    let game = TestData.EuropeanChampionshipWithChat
    let chatLine = game.chatLog[36]
    BoardView(
        boardPosition: chatLine.variation!.position,
        variation: chatLine.variation,
        showsCoordinate: true,
        highlightCoordinates: [[2, 2]]
    )
}

#Preview("Board markers", traits: .fixedLayout(width: 375, height: 375)) {
    let position = TestData.Resigned9x9Japanese.currentPosition
    BoardView(
        boardPosition: position,
        showsCoordinate: true,
        markups: .constant([
            BoardPoint(row: 2, column: 2): BoardMarkup(label: "A"),
            BoardPoint(row: 3, column: 3): BoardMarkup(shapes: [.triangle]),
            BoardPoint(row: 4, column: 4): BoardMarkup(shapes: [.square]),
            BoardPoint(row: 5, column: 5): BoardMarkup(shapes: [.circle]),
            BoardPoint(row: 6, column: 6): BoardMarkup(shapes: [.cross])
        ])
    )
}

#Preview("9×9 Undo request with coordinates", traits: .fixedLayout(width: 200, height: 200)) {
    let game = {
        let game = TestData.Resigned9x9Japanese
        game.undoRequest = OGSUndoRequest(
            moveNumber: game.currentPosition.lastMoveNumber,
            moveCount: 2
        )
        return game
    }()
    BoardView(
        boardPosition: game.currentPosition,
        showsCoordinate: true,
        undoRequestCoordinates: game.undoRequestCoordinates
    )
}

#Preview("Scored 19×19", traits: .fixedLayout(width: 500, height: 500)) {
    BoardView(boardPosition: TestData.Scored19x19Korean.currentPosition)
}

#Preview("Game card thumbnail", traits: .fixedLayout(width: 120, height: 120)) {
    BoardView(boardPosition: TestData.Scored19x19Korean.currentPosition)
}

#Preview("Compact handicap thumbnail", traits: .fixedLayout(width: 44, height: 44)) {
    BoardView(
        boardPosition: TestData.Resigned19x19HandicappedWithInitialState.currentPosition
    )
}
#endif
