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
                .stroke(Color.black)
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
                    let stoneRect = CGRect(x: CGFloat(column) * size + 1, y: CGFloat(row) * size + 1, width: size - 2, height: size - 2)
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
                let scoringRectSize = max(size / 4, 5)
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
        
        return ZStack {
            Path(whiteLivingPath).fill(Color.white)
            Path(whiteLivingPath).stroke(Color.gray)
            Path(blackLivingPath).fill(Color.black)
            
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
                    .stroke(boardPosition.nextToMove == .black ? Color.gray : Color.white, lineWidth: size > 20 ? 2 : 1)
                } else {
                    Path { path in
                        path.addEllipse(in: CGRect(
                                            x: CGFloat(lastColumn) * size + size / 4,
                                            y: CGFloat(lastRow) * size + size / 4,
                                            width: size / 2,
                                            height: size / 2))
                    }
                    .stroke(boardPosition.nextToMove == .black ? Color.gray : Color.white, lineWidth: size > 20 ? 2 : 1)
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
        return Group {
            BoardView(boardPosition: boardPosition)
                .previewLayout(.fixed(width: 375, height: 500))
            BoardView(boardPosition: game2.currentPosition)
                .previewLayout(.fixed(width: 375, height: 500))
            BoardView(boardPosition: boardPosition).colorScheme(.dark)
                .previewLayout(.fixed(width: 375, height: 500))
        }
    }
}
