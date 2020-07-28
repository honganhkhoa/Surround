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
    var boardSize: Int
    
    var body: some View {
        let size = cellSize(geometry: geometry, boardSize: boardSize)
        return Path { path in
            for i in 0..<boardSize {
                path.move(to: CGPoint(x: size / 2, y: (CGFloat(i) + 0.5) * size))
                path.addLine(to: CGPoint(x: (CGFloat(boardSize) - 0.5) * size, y:(CGFloat(i) + 0.5) * size))
                
                path.move(to: CGPoint(x: (CGFloat(i) + 0.5) * size, y: size / 2))
                path.addLine(to: CGPoint(x: (CGFloat(i) + 0.5) * size, y: (CGFloat(boardSize) - 0.5) * size))
            }
        }
        .stroke(Color.black)
        .background(Color(red: 0.86, green: 0.69, blue: 0.42, opacity: 1.00).shadow(radius: 2))
        .frame(width: size * CGFloat(boardSize), height: size * CGFloat(boardSize))
    }
}

struct Stones: View {
    var boardPosition: BoardPosition
    var geometry: GeometryProxy

    var body: some View {
        let boardSize = boardPosition.boardSize
                
        let size = cellSize(geometry: geometry, boardSize: boardSize)
        let whiteLivingPath = CGMutablePath()
        let blackLivingPath = CGMutablePath()
        let whiteCapturedPath = CGMutablePath()
        let blackCapturedPath = CGMutablePath()
        let whiteScoreIndicator = CGMutablePath()
        let blackScoreIndicator = CGMutablePath()
        for row in 0..<boardSize {
            for column in 0..<boardSize {
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
                if let scores = boardPosition.gameScores {
                    let scoringRectSize = max(size / 4, 5)
                    let scoringRectPadding = (size - scoringRectSize) / 2
                    let scoringRect = CGRect(
                        x: CGFloat(column) * size + scoringRectPadding,
                        y: CGFloat(row) * size + scoringRectPadding,
                        width: scoringRectSize,
                        height: scoringRectSize)
                    if scores.black.scoringPositions.contains([row, column]) {
                        blackScoreIndicator.addRect(scoringRect)
                    } else if scores.white.scoringPositions.contains([row, column]) {
                        whiteScoreIndicator.addRect(scoringRect)
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
                Path { path in
                    path.addEllipse(in: CGRect(
                                        x: CGFloat(lastColumn) * size + size / 4,
                                        y: CGFloat(lastRow) * size + size / 4,
                                        width: size / 2,
                                        height: size / 2))
                }
                .stroke(boardPosition.nextToMove == .black ? Color.gray : Color.white, lineWidth: size > 20 ? 2 : 1)
            }
            
            if boardPosition.gameScores != nil {
                Path(whiteScoreIndicator).fill(Color.white)
                Path(blackScoreIndicator).fill(Color.black)
            }
        }
        .frame(width: size * CGFloat(boardSize), height: size * CGFloat(boardSize))
    }
}

struct BoardView: View {
    @Binding var boardPosition: BoardPosition
    
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
        return GeometryReader { geometry in
            ZStack(alignment: .center) {
                Goban(geometry: geometry, boardSize: self.boardPosition.boardSize)
                Stones(boardPosition: boardPosition, geometry: geometry)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).aspectRatio(1, contentMode: .fit)
        }
    }
}

struct BoardView_Previews: PreviewProvider {
    static var previews: some View {
        let game = TestData.Scored19x19Korean
        let boardPosition = game.currentPosition
        return Group {
            BoardView(boardPosition: .constant(boardPosition))
                .previewLayout(.fixed(width: 375, height: 500))
            BoardView(boardPosition: .constant(boardPosition)).colorScheme(.dark)
                .previewLayout(.fixed(width: 375, height: 500))
        }
    }
}
