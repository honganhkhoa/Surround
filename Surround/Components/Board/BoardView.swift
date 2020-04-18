//
//  BoardView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/18/20.
//

import SwiftUI

func cellSize(geometry: GeometryProxy, boardSize: Int) -> CGFloat {
    return CGFloat(
        floor(min(geometry.size.width, geometry.size.height) / CGFloat(boardSize) / 2) * 2
        )
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
        .stroke(Color.black).frame(width: size * CGFloat(boardSize), height: size * CGFloat(boardSize), alignment: .center)
        .background(Color(red: 0.86, green: 0.69, blue: 0.42, opacity: 1.00).shadow(radius: 2))
    }
}

struct Cell: View {
    var boardPosition: BoardPosition
    var parentGeometry: GeometryProxy
    var row: Int
    var column: Int
    
    var scoreIndicator: some View {
        let size = max(cellSize(geometry: self.parentGeometry, boardSize: self.boardPosition.boardSize) / 4, 5)
        if boardPosition.gameScores?.black.scoringPositions.contains([row, column]) ?? false {
            return AnyView(Rectangle().fill(Color.black).frame(width: size, height: size))
        }
        if boardPosition.gameScores?.white.scoringPositions.contains([row, column]) ?? false {
            return AnyView(Rectangle().fill(Color.white).frame(width: size, height: size))
        }
        return AnyView(EmptyView())
    }
    
    var body: some View {
        let size = cellSize(geometry: self.parentGeometry, boardSize: self.boardPosition.boardSize)
        var isLastMove = false
        if case .placeStone(let lastRow, let lastColumn) = self.boardPosition.lastMove {
            isLastMove = lastRow == row && lastColumn == column
        }
        if case .hasStone(let color) = self.boardPosition[row, column] {
            return AnyView(
                ZStack {
                    Circle().fill(color == .black ? Color.black : Color.white).padding(1)
                    Circle().stroke(Color.black).padding(1)
                    if isLastMove {
                        Circle().stroke(color == .black ? Color.white : Color.black, lineWidth: size > 20 ? 2 : 1).padding(size / 4)
                    }
                    scoreIndicator
                }
                .frame(width: size, height: size, alignment: .center)
                .contentShape(Rectangle())
                .opacity(self.boardPosition.removedStones?.contains([row, column]) ?? false ? 0.5 : 1)
            )
        } else {
            return AnyView(
                ZStack {
                    EmptyView()
                    scoreIndicator
                }.frame(width: size, height: size, alignment: .center)
            )
        }
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
            ZStack {
                Goban(geometry: geometry, boardSize: self.boardPosition.boardSize)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach((0..<self.boardPosition.boardSize), id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach((0..<self.boardPosition.boardSize), id: \.self) { column in
                                Cell(boardPosition: self.boardPosition, parentGeometry: geometry, row: row, column: column)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct BoardView_Previews: PreviewProvider {
    static var previews: some View {
        let game = TestData.Resigned19x19HandicappedWithInitialState
        let boardPosition = game.currentPosition
        return Group {
            BoardView(boardPosition: .constant(boardPosition))
                .previewLayout(.fixed(width: 375, height: 500))
            BoardView(boardPosition: .constant(boardPosition)).colorScheme(.dark)
                .previewLayout(.fixed(width: 375, height: 500))
        }
    }
}
