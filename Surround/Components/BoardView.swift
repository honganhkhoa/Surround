//
//  BoardView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/18/20.
//

import SwiftUI

func stoneSize(geometry: GeometryProxy, boardSize: Int) -> CGFloat {
    return CGFloat(
        floor(min(geometry.size.width, geometry.size.height) / CGFloat(boardSize)))
}

enum StoneRemovalOption: Int {
    case toggleGroup
    case toggleSinglePoint
}

struct Goban: View {
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
    @State var selectionFeedbackGenerator: UISelectionFeedbackGenerator? = nil

    @Setting(.hapticsFeedback) var hapticsFeedbback: Bool
    
    var body: some View {
        let size = stoneSize(geometry: geometry, boardSize: max(width, height))
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
                    ForEach(0..<width) { col in
                        Text("\(coordinates[col])").font(.system(size: size))
                            .minimumScaleFactor(0.2)
                            .foregroundColor(.black)
                            .frame(width: size, height: size)
                            .position(x: (CGFloat(col) + 0.5) * size, y: -0.5 * size)
                    }
                    ForEach(0..<height) { row in
                        Text("\(height - row)").font(.system(size: size))
                            .minimumScaleFactor(0.2)
                            .foregroundColor(.black)
                            .frame(width: size, height: size)
                            .position(x: -0.5 * size, y: (CGFloat(row) + 0.5) * size)
                    }
                }
                Path { path in
                    for i in 0..<height {
                        path.move(to: CGPoint(x: size / 2, y: (CGFloat(i) + 0.5) * size))
                        path.addLine(to: CGPoint(x: (CGFloat(width) - 0.5) * size, y:(CGFloat(i) + 0.5) * size))
                    }
                    for i in 0..<width {
                        path.move(to: CGPoint(x: (CGFloat(i) + 0.5) * size, y: size / 2))
                        path.addLine(to: CGPoint(x: (CGFloat(i) + 0.5) * size, y: (CGFloat(height) - 0.5) * size))
                    }
                }
                .stroke(Color.black, lineWidth: size < 10 ? 0.5 : 1)
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
                    .stroke(Color(highlightColor), lineWidth: 2)
                }
            }
        }
        .frame(width: size * CGFloat(width), height: size * CGFloat(height))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged({ value in
                    if self.selectionFeedbackGenerator == nil && self.hapticsFeedbback {
                        self.selectionFeedbackGenerator = UISelectionFeedbackGenerator()
                        self.selectionFeedbackGenerator?.prepare()
                    }
                    selectedPoint.wrappedValue = nil
                    highlightedRow = Int((value.location.y / size - 0.5).rounded())
                    highlightedColumn = Int((value.location.x / size - 0.5).rounded())
                    if highlightedColumn >= 0 && highlightedColumn < width && highlightedRow >= 0 && highlightedRow < height {
                        if hoveredPoint.wrappedValue != [highlightedRow, highlightedColumn] {
                            hoveredPoint.wrappedValue = [highlightedRow, highlightedColumn]
                            self.selectionFeedbackGenerator?.selectionChanged()
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
                            if self.hapticsFeedbback {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            }
                        } else {
                            if self.hapticsFeedbback {
                                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            }
                        }
                    }
                    hoveredPoint.wrappedValue = nil
                    self.selectionFeedbackGenerator = nil
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
                        Text("\(label)")
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
    @ObservedObject var boardPosition: BoardPosition
    var variation: Variation?
    var geometry: GeometryProxy
    var isLastMovePending = false

    var body: some View {
        let width = boardPosition.width
        let height = boardPosition.height
                
        let size = stoneSize(geometry: geometry, boardSize: max(width, height))
        let whiteLivingPath = CGMutablePath()
        let blackLivingPath = CGMutablePath()
        let whiteCapturedPath = CGMutablePath()
        let blackCapturedPath = CGMutablePath()
        let whiteScoreIndicator = CGMutablePath()
        let blackScoreIndicator = CGMutablePath()
        let dameIndicator = CGMutablePath()
        let whiteEstimatedScore = CGMutablePath()
        let blackEstimatedScore = CGMutablePath()

        let whiteShadowPath1 = CGMutablePath()
        let whiteShadowPath2 = CGMutablePath()
        let blackShadowPath1 = CGMutablePath()
        let blackShadowPath2 = CGMutablePath()
        let drawsShadow = size >= 14
        let shadowOffset: CGFloat = size > 30 ? 2 : 1

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
                            if drawsShadow {
                                // Separate shadows of adjacent stones
                                if (row + column) % 2 == 0 {
                                    whiteShadowPath1.addEllipse(in: stoneRect)
                                } else {
                                    whiteShadowPath2.addEllipse(in: stoneRect)
                                }
                            }
                            whiteLivingPath.addEllipse(in: stoneRect)
                        } else {
                            if drawsShadow {
                                if (row + column) % 2 == 0 {
                                    blackShadowPath1.addEllipse(in: stoneRect)
                                } else {
                                    blackShadowPath2.addEllipse(in: stoneRect)
                                }
                            }
                            blackLivingPath.addEllipse(in: stoneRect)
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
        
        return ZStack {
            if drawsShadow {
                Path(whiteLivingPath).fill(Color(red: 0.75, green: 0.75, blue: 0.75))
                    .shadow(radius: 2, x: shadowOffset, y:shadowOffset)
                Path(whiteLivingPath).stroke(Color.gray, lineWidth: 0.5)
                Path(whiteShadowPath1).fill(Color(UIColor.clear)).shadow(color: Color.white, radius: size / 4, x: -size / 4, y: -size / 4)
                    .clipShape(Path(whiteShadowPath1))
                Path(whiteShadowPath2).fill(Color(UIColor.clear)).shadow(color: Color.white, radius: size / 4, x: -size / 4, y: -size / 4)
                    .clipShape(Path(whiteShadowPath2))

                Path(blackLivingPath).fill(Color.black)
                    .shadow(radius: 2, x: shadowOffset, y:shadowOffset)
                Path(blackShadowPath1).fill(Color(UIColor.clear)).shadow(color: Color(red: 0.45, green: 0.45, blue: 0.45), radius: size / 4, x: -size / 4, y: -size / 4)
                    .clipShape(Path(blackShadowPath1))
                Path(blackShadowPath2).fill(Color(UIColor.clear)).shadow(color: Color(red: 0.45, green: 0.45, blue: 0.45), radius: size / 4, x: -size / 4, y: -size / 4)
                    .clipShape(Path(blackShadowPath2))
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

            if let variation = variation {
                VariationNumberings(variation: variation, cellSize: size)
            } else if case .placeStone(let lastRow, let lastColumn) = boardPosition.lastMove {
                if case .hasStone(let lastColor) = boardPosition[lastRow, lastColumn] {
                    if boardPosition.estimatedScores == nil {
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
        let size = stoneSize(geometry: geometry, boardSize: max(width, height))

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
        .onChange(of: stoneRemovalSelectedPoints.wrappedValue) { newSelectedPoints in
            if newSelectedPoints.count == 0 {
                hoveredGroup.removeAll()
            }
        }
    }
}

struct MarkerOverlay: View {
    @ObservedObject var boardPosition: BoardPosition
    var geometry: GeometryProxy
    var highlightCoordinates: [[Int]]

    var body: some View {
        let width = boardPosition.width
        let height = boardPosition.height
                
        let size = stoneSize(geometry: geometry, boardSize: max(width, height))
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

struct BoardView: View {
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
                .allowsHitTesting(playable && displayedPosition.estimatedScores == nil)
                .onChange(of: hoveredPoint) { value in
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
                .onChange(of: selectedPoint) { value in
                    if let selectedPoint = value {
                        newMove.wrappedValue = .placeStone(selectedPoint[0], selectedPoint[1])
                    } else {
                        newMove.wrappedValue = nil
                    }
                }
                Stones(boardPosition: displayedPosition, variation: variation, geometry: boardGeometry, isLastMovePending: newMove.wrappedValue != nil)
                MarkerOverlay(boardPosition: boardPosition, geometry: boardGeometry, highlightCoordinates: highlightCoordinates)
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
                Color(red: 0.86, green: 0.69, blue: 0.42).cornerRadius(cornerRadius).shadow(radius: 2)
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
    }
}

struct BoardView_Previews: PreviewProvider {
    static var previews: some View {
        let game = TestData.Scored19x19Korean
        let boardPosition = game.currentPosition
//        let game2 = TestData.Scored15x17
        let game3 = TestData.Resigned19x19HandicappedWithInitialState
//        let game4 = TestData.Ongoing19x19HandicappedWithNoInitialState
        let game5 = TestData.EuropeanChampionshipWithChat
        let chatLine = game5.chatLog[36]
        return Group {
            BoardView(boardPosition: chatLine.variation!.position, variation: chatLine.variation, showsCoordinate: true, highlightCoordinates: [[2, 2]])
                .previewLayout(.fixed(width: 375, height: 375))
            BoardView(boardPosition: boardPosition)
                .previewLayout(.fixed(width: 500, height: 500))
            BoardView(boardPosition: boardPosition)
                .previewLayout(.fixed(width: 120, height: 120))
//            BoardView(boardPosition: game2.currentPosition)
//                .previewLayout(.fixed(width: 375, height: 375))
            BoardView(boardPosition: game3.currentPosition)
                .previewLayout(.fixed(width: 80, height: 80))
//            BoardView(boardPosition: game4.currentPosition)
//                .previewLayout(.fixed(width: 375, height: 500))
        }
    }
}
