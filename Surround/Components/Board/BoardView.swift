//
//  BoardView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/18/20.
//

import SwiftUI

func cellSize(geometry: GeometryProxy, boardSize: Int) -> CGFloat {
    return CGFloat(
        floor(min(geometry.size.width, geometry.size.height) / CGFloat(boardSize) / 2) * 2)
}

struct Stone: View {
    var color: StoneColor
    var shadowRadius: CGFloat = 0.0
    
    var body: some View {
        Group {
            switch color {
            case .black:
                if shadowRadius > 0 {
                    Circle().fill(Color.black).shadow(radius: shadowRadius)
                } else {
                    Circle().fill(Color.black)
                }
            case .white:
                ZStack {
                    if shadowRadius > 0 {
                        Circle().fill(Color.white).shadow(radius: shadowRadius)
                    } else {
                        Circle().fill(Color.white)
                    }
                    Circle().stroke(Color.gray)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct Goban: View {
    var geometry: GeometryProxy
    var width: Int
    var height: Int
    var editable = false
    @State var currentRow = -1
    @State var currentColumn = -1
    var hoveredPoint: Binding<[Int]?> = .constant(nil)
    var isHoveredPointValid: Bool? = nil
    var selectedPoint: Binding<[Int]?> = .constant(nil)

    var body: some View {
        let size = cellSize(geometry: geometry, boardSize: max(width, height))
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
        return Group {
            ZStack {
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
                if hoveredPoint.wrappedValue != nil {
                    Path { path in
                        path.move(to: CGPoint(x: size / 2, y: (CGFloat(currentRow) + 0.5) * size))
                        path.addLine(to: CGPoint(x: (CGFloat(width) - 0.5) * size, y:(CGFloat(currentRow) + 0.5) * size))

                        path.move(to: CGPoint(x: (CGFloat(currentColumn) + 0.5) * size, y: size / 2))
                        path.addLine(to: CGPoint(x: (CGFloat(currentColumn) + 0.5) * size, y: (CGFloat(height) - 0.5) * size))
                    }
                    .stroke(isHoveredPointValid ?? false ? Color.green : Color.red, lineWidth: 2)
                }
            }
        }
        .frame(width: size * CGFloat(width), height: size * CGFloat(height))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged({ value in
                    selectedPoint.wrappedValue = nil
                    currentRow = Int((value.location.y / size - 0.5).rounded())
                    currentColumn = Int((value.location.x / size - 0.5).rounded())
                    if currentColumn >= 0 && currentColumn < width && currentRow >= 0 && currentRow < height {
                        hoveredPoint.wrappedValue = [currentRow, currentColumn]
                    } else {
                        hoveredPoint.wrappedValue = nil
                    }
                })
                .onEnded { _ in
                    if isHoveredPointValid ?? false {
                        if let hoveredPoint = hoveredPoint.wrappedValue {
                            selectedPoint.wrappedValue = hoveredPoint
                        }
                    }
                    hoveredPoint.wrappedValue = nil
                }
        )
    }
}

struct Stones: View {
    var boardPosition: BoardPosition
    var geometry: GeometryProxy
    var isLastMovePending = false

    var body: some View {
        let width = boardPosition.width
        let height = boardPosition.height
                
        let size = cellSize(geometry: geometry, boardSize: max(width, height))
        let whiteLivingPath = CGMutablePath()
        let blackLivingPath = CGMutablePath()
        let whiteCapturedPath = CGMutablePath()
        let blackCapturedPath = CGMutablePath()
        let whiteScoreIndicator = CGMutablePath()
        let blackScoreIndicator = CGMutablePath()
        let whiteEstimatedScore = CGMutablePath()
        let blackEstimatedScore = CGMutablePath()
        
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
                        } else {
                            blackLivingPath.addEllipse(in: stoneRect)
                        }
                    }
                }
                let scoringRectSize = max(size / 4, 2)
                let scoringRectPadding = (size - scoringRectSize) / 2
                let scoringRect = CGRect(
                    x: CGFloat(column) * size + scoringRectPadding,
                    y: CGFloat(row) * size + scoringRectPadding,
                    width: scoringRectSize,
                    height: scoringRectSize)
                if let scores = boardPosition.gameScores {
                    if scores.black.scoringPositions.contains([row, column]) {
                        blackScoreIndicator.addRect(scoringRect)
                    } else if scores.white.scoringPositions.contains([row, column]) {
                        whiteScoreIndicator.addRect(scoringRect)
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
        
        let lastMoveIndicatorWidth: CGFloat = size > 20 ? 2 : (size > 10 ? 1 : 0.5)
        
        return ZStack {
            Path(whiteLivingPath).fill(Color.white)
            Path(whiteLivingPath).stroke(Color.gray)
            Path(blackLivingPath).fill(Color.black)
            if size > 20 {
                Path(blackLivingPath).fill(Color(UIColor.clear)).shadow(color: Color(red: 0.5, green: 0.5, blue: 0.5), radius: size / 4, x: -size / 4, y: -size / 4)
                    .clipShape(Path(blackLivingPath))
                Path(whiteLivingPath).fill(Color(UIColor.clear)).shadow(color: Color(red: 0.85, green: 0.85, blue: 0.85), radius: size / 4, x: -size / 4, y: -size / 4)
                    .clipShape(Path(whiteLivingPath))
            }
            
            if boardPosition.removedStones != nil {
                Path(whiteCapturedPath).fill(Color.white).opacity(0.5)
                Path(whiteCapturedPath).stroke(Color.gray)
                Path(blackCapturedPath).fill(Color.black).opacity(0.5)
            }

            if case .placeStone(let lastRow, let lastColumn) = boardPosition.lastMove {
                if isLastMovePending {
                    Path { path in
                        let centerX = CGFloat(lastColumn) * size + size / 2
                        let centerY = CGFloat(lastRow) * size + size / 2
                        path.move(to: CGPoint(x: centerX - size / 4, y: centerY))
                        path.addLine(to: CGPoint(x: centerX + size / 4, y: centerY))
                        path.move(to: CGPoint(x: centerX, y: centerY - size / 4))
                        path.addLine(to: CGPoint(x: centerX, y: centerY + size / 4))
                    }
                    .stroke(boardPosition.nextToMove == .black ? Color.gray : Color.white, lineWidth: lastMoveIndicatorWidth)
                } else {
                    Path { path in
                        path.addEllipse(in: CGRect(
                                            x: CGFloat(lastColumn) * size + size / 4,
                                            y: CGFloat(lastRow) * size + size / 4,
                                            width: size / 2,
                                            height: size / 2))
                    }
                    .stroke(boardPosition.nextToMove == .black ? Color.gray : Color.white, lineWidth: lastMoveIndicatorWidth)
                }
            }
            
            if boardPosition.gameScores != nil {
                Path(whiteScoreIndicator).fill(Color.white)
                Path(blackScoreIndicator).fill(Color.black)
            }
            
            if boardPosition.estimatedScores != nil {
                Path(whiteEstimatedScore).fill(Color.white)
                Path(blackEstimatedScore).fill(Color.black)
            }
        }
        .frame(width: size * CGFloat(width), height: size * CGFloat(height))
    }
}

struct BoardView: View {
    var boardPosition: BoardPosition
    var editable = false
    var newMove: Binding<Move?> = .constant(nil)
    var newPosition: Binding<BoardPosition?> = .constant(nil)
    @State var hoveredPoint: [Int]? = nil
    @State var isHoveredPointValid: Bool? = nil
    @State var selectedPoint: [Int]? = nil
    
//        .onTapGesture {
//            do {
//                print("Making move... (\(row), \(column))")
//                self.boardPosition = try self.boardPosition.makeMove(move: .placeStone(row, column))
//                print("Done")
//            } catch {
//                print("Move error")
//            }
//        }
    
    var body: some View {
//        self.boardPosition.printPosition()
        let displayedPosition = (newMove.wrappedValue != nil && newPosition.wrappedValue != nil) ?
            newPosition.wrappedValue! : boardPosition
        return GeometryReader { geometry in
            ZStack(alignment: .center) {
                Color(red: 0.86, green: 0.69, blue: 0.42, opacity: 1.00).shadow(radius: 2)
                Goban(
                    geometry: geometry,
                    width: boardPosition.width,
                    height: boardPosition.height,
                    editable: editable,
                    hoveredPoint: $hoveredPoint,
                    isHoveredPointValid: isHoveredPointValid,
                    selectedPoint: $selectedPoint
                )
                .allowsHitTesting(editable)
                .onChange(of: hoveredPoint) { value in
                    if let hoveredPoint = hoveredPoint {
                        do {
                            newPosition.wrappedValue = try boardPosition.makeMove(move: .placeStone(hoveredPoint[0], hoveredPoint[1]))
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
                Stones(boardPosition: displayedPosition, geometry: geometry, isLastMovePending: newMove.wrappedValue != nil)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).aspectRatio(1, contentMode: .fit)
        }
    }
}

struct BoardView_Previews: PreviewProvider {
    static var previews: some View {
        let game = TestData.Scored19x19Korean
        let boardPosition = game.currentPosition
        let game2 = TestData.Scored15x17
        let game3 = TestData.Resigned19x19HandicappedWithInitialState
        let game4 = TestData.Ongoing19x19HandicappedWithNoInitialState
        return Group {
            BoardView(boardPosition: boardPosition)
                .previewLayout(.fixed(width: 500, height: 500))
            BoardView(boardPosition: boardPosition)
                .previewLayout(.fixed(width: 120, height: 120))
            BoardView(boardPosition: game2.currentPosition)
                .previewLayout(.fixed(width: 375, height: 500))
            BoardView(boardPosition: game3.currentPosition)
                .previewLayout(.fixed(width: 375, height: 500))
            BoardView(boardPosition: game4.currentPosition)
                .previewLayout(.fixed(width: 375, height: 500))
            BoardView(boardPosition: boardPosition).colorScheme(.dark)
                .previewLayout(.fixed(width: 375, height: 500))
        }
    }
}
