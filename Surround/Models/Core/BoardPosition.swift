//
//  BoardPosition.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/18/20.
//

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
    var boardSize: Int
    var board: [[PointState]]
    var nextToMove: StoneColor
    var previousPosition: BoardPosition?
    var lastMove: Move?
    var captures: [StoneColor: Int] = [.black: 0, .white: 0]
    var removedStones: Set<[Int]>?
    var gameScores: GameScores?
    
    init(boardSize: Int) {
        self.boardSize = boardSize
        self.board = Array(repeating: Array(repeating: .empty, count: self.boardSize), count: self.boardSize)
        self.nextToMove = .black
    }
    
    init(fromPreviousPosition previousPosition: BoardPosition, lastMove: Move) {
        self.boardSize = previousPosition.boardSize
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
        if self.boardSize != otherPosition.boardSize {
            return false
        }
        
        for row in 0..<self.boardSize {
            for column in 0..<self.boardSize {
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
            return neighbor[0] >= 0 && neighbor[0] < self.boardSize && neighbor[1] >= 0 && neighbor[1] < self.boardSize
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
        for i in 0..<self.boardSize {
            print((0..<self.boardSize).map({
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
}
