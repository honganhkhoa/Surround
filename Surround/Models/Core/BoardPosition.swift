//
//  BoardPosition.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/18/20.
//

import Dispatch

enum PointState {
    case empty
    case hasStone(StoneColor)
}

enum StoneColor: String, Codable {
    case black
    case white
    func opponentColor() -> StoneColor {
        if case .black = self {
            return .white
        } else {
            return .black
        }
    }
}

enum Move {
    case pass
    case placeStone(Int, Int)
}

enum MoveError: Error {
    case pointAlreadyOccupied
    case illegalKoMove
    case suicidalMove
}

class BoardPosition {
    var width: Int
    var height: Int
    var board: [[PointState]]
    var nextToMove: StoneColor
    var previousPosition: BoardPosition?
    var lastMove: Move?
    var captures: [StoneColor: Int] = [.black: 0, .white: 0]
    var removedStones: Set<[Int]>?
    var gameScores: GameScores?
    var estimatedScores: [[PointState]]?
    
    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.board = Array(repeating: Array(repeating: .empty, count: self.width), count: self.height)
        self.nextToMove = .black
    }
    
    init(fromPreviousPosition previousPosition: BoardPosition, lastMove: Move) {
        self.width = previousPosition.width
        self.height = previousPosition.height
        self.lastMove = lastMove
        self.previousPosition = previousPosition
        self.nextToMove = previousPosition.nextToMove.opponentColor()
        self.board = previousPosition.board
    }
    
    subscript(row: Int, column: Int) -> PointState {
        get {
            return self.board[row][column]
        }
        set {
            self.board[row][column] = newValue
        }
    }
    
    subscript(point: [Int]) -> PointState {
        get {
            return self[point[0], point[1]]
        }
        set {
            self[point[0], point[1]] = newValue
        }
    }
    
    func hasTheSamePosition(with otherPosition: BoardPosition) -> Bool {
        if self.width != otherPosition.width || self.height != otherPosition.height {
            return false
        }
        
        for row in 0..<self.height {
            for column in 0..<self.width {
                switch (self[row, column], otherPosition[row, column]) {
                case (.hasStone(let color), .hasStone(let otherColor)):
                    if color != otherColor {
                        return false
                    }
                case (.empty, .empty):
                    break
                default:
                    return false
                }
            }
        }
        return true
    }
    
    func putStone(row: Int, column: Int, color: StoneColor) {
        self.board[row][column] = .hasStone(color)
    }
    
    func neighbors(row: Int, column: Int) -> Set<[Int]> {
        let neighbors = [[-1, 0], [0, 1], [1, 0], [0, -1]].map { delta in
            return [row + delta[0], column + delta[1]]
        }
        
        return Set(neighbors.filter { neighbor in
            return neighbor[0] >= 0 && neighbor[0] < self.height && neighbor[1] >= 0 && neighbor[1] < self.width
        })
    }
    
    func neighbors(point: [Int]) -> Set<[Int]> {
        return self.neighbors(row: point[0], column: point[1])
    }
    
    func stoneGroup(row: Int, column: Int) -> Set<[Int]> {
        guard case .hasStone(let originColor) = self[row, column] else {
            return []
        }
        var result = Set([[row, column]])
        var currentPoints = Set([[row, column]])
        while currentPoints.count > 0 {
            var nextPoints = Set<[Int]>()
            for point in currentPoints {
                for neighbor in self.neighbors(point: point) {
                    if !result.contains(neighbor) {
                        if case .hasStone(let color) = self[neighbor] {
                            if color == originColor {
                                result.insert(neighbor)
                                nextPoints.insert(neighbor)
                            }
                        }
                    }
                }
            }
            currentPoints = nextPoints
        }
        return result
    }
    
    func stoneGroup(point: [Int]) -> Set<[Int]> {
        return self.stoneGroup(row: point[0], column: point[1])
    }
    
    func liberties(group: Set<[Int]>) -> Set<[Int]> {
        var liberties = Set<[Int]>()
        for point in group {
            for neighbor in self.neighbors(point: point) {
                if case .empty = self[neighbor] {
                    liberties.insert(neighbor)
                }
            }
        }
        return liberties
    }
    
    func captureGroup(group: Set<[Int]>) {
        guard group.count > 0 else {
            return
        }
        
        guard case .hasStone(let color) = self[group.randomElement()!] else {
            return
        }

        self.captures[color.opponentColor(), default: 0] += group.count
        for point in group {
            self[point] = .empty
        }
    }
    
    func makeMove(move: Move) throws -> BoardPosition {
        switch move {
        case .pass:
            return BoardPosition(fromPreviousPosition: self, lastMove: move)
        case .placeStone(let row, let column):
            if case .hasStone = self[row, column] {
                throw MoveError.pointAlreadyOccupied
            }
            let newPosition = BoardPosition(fromPreviousPosition: self, lastMove: move)
            newPosition[row, column] = .hasStone(self.nextToMove)
            
            // Capture
            var hasCapture = false
            for neighbor in newPosition.neighbors(row: row, column: column) {
                if case .hasStone(let color) = newPosition[neighbor] {
                    if color == self.nextToMove.opponentColor() {
                        let neighborGroup = newPosition.stoneGroup(point: neighbor)
                        if newPosition.liberties(group: neighborGroup).count == 0 {
                            newPosition.captureGroup(group: neighborGroup)
                            hasCapture = true
                        }
                    }
                }
            }
            
            if hasCapture {
                if self.previousPosition?.hasTheSamePosition(with: newPosition) ?? false {
                    throw MoveError.illegalKoMove
                }
            } else {
                if newPosition.liberties(group: newPosition.stoneGroup(row: row, column: column)).count == 0 {
                    throw MoveError.suicidalMove
                }
            }
            
            return newPosition
        }
    }
    
    func printPosition() {
        for i in 0..<self.height {
            print((0..<self.width).map({
                switch self[i, $0] {
                case .empty:
                    return " "
                case .hasStone(let color):
                    return color == .black ? "x" : "o"
                }
            }).joined(separator: ""))
        }
    }
    
    static func points(fromPositionString positionString: String) -> Set<[Int]> {
        var result = Set<[Int]>()
        for index in stride(from: 0, to: positionString.count, by: 2) {
            let column = positionString[positionString.index(positionString.startIndex, offsetBy: index)].asciiValue! - "a".first!.asciiValue!
            let row = positionString[positionString.index(positionString.startIndex, offsetBy: index + 1)].asciiValue! - "a".first!.asciiValue!
            result.insert([Int(row), Int(column)])
        }
        return result
    }
    
    func estimateScore() {
        DispatchQueue.global().async { [self] in
            var data = board.joined().map({ state -> CInt in
                switch state {
                case .empty:
                    return 0
                case .hasStone(let color):
                    return color == .white ? -1 : 1
                }
            })
            
            print(data)
            se_estimate(CInt(width), CInt(height), &data, nextToMove == .white ? -1 : 1, 1000, Float(0.3))
            print(data)

            DispatchQueue.main.async { [self] in
                estimatedScores = Array(repeating: Array(repeating: .empty, count: width), count: height)
                for i in 0..<height * width {
                    let row = i / width
                    let column = i % width
                    if data[i] == 0 {
                        estimatedScores![row][column] = .empty
                    } else if data[i] == -1 {
                        estimatedScores![row][column] = .hasStone(.white)
                    } else {
                        estimatedScores![row][column] = .hasStone(.black)
                    }
                }
            }
        }
    }
}
