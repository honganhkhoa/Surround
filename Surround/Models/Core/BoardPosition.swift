//
//  BoardPosition.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/18/20.
//

import Foundation
import Dispatch
import Combine

private let coordinateLabels = "abcdefghijklmnopqrstuvwxyz".map { $0 }

enum PointState: Equatable {
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

enum Move: Equatable {
    case placeStone(Int, Int)
    case pass
    
    func toOGSString() -> String {
        switch self {
        case .placeStone(let row, let column):
            return "\(coordinateLabels[column])\(coordinateLabels[row])"
        case .pass:
            return ".."
        }
    }
    
    static func fromMoveString(moveString: String) -> [Move] {
        var result = [Move]()
        for index in stride(from: 0, to: moveString.count, by: 2) {
            let column = moveString[moveString.index(moveString.startIndex, offsetBy: index)].asciiValue! - "a".first!.asciiValue!
            let row = moveString[moveString.index(moveString.startIndex, offsetBy: index + 1)].asciiValue! - "a".first!.asciiValue!
            result.append(.placeStone(Int(row), Int(column)))
        }
        return result
    }
}

enum MoveError: Error {
    case pointAlreadyOccupied
    case illegalKoMove
    case suicidalMove
    case unexpectedInvalidMove
}

class TerritoryGroup: Equatable, Hashable {
    var points: Set<[Int]>
    var state: PointState
    var isDame: Bool
    var neighbors = Set<TerritoryGroup>()

    var debugDescription: String {
        "\(points.count) points: \(points.map({ "[\($0[0]), \($0[1])]" }).joined(separator: ", "))"
    }
    
    init(points: Set<[Int]>, state: PointState, isDame: Bool) {
        self.points = points
        self.state = state
        self.isDame = isDame
    }
    
    static func == (lhs: TerritoryGroup, rhs: TerritoryGroup) -> Bool {
        return lhs.points == rhs.points
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(points)
    }

    var isTerritory = false
    var territoryColor = StoneColor.black
    func computeTerritory() {
        guard state == .empty else {
            return
        }
        
        for neighbor in neighbors {
            if case .hasStone(let color) = neighbor.state {
                for neighbor in neighbors {
                    if neighbor.state != .empty && neighbor.state != .hasStone(color) {
                        return
                    }
                }
                isTerritory = true
                territoryColor = color
                break
            }
        }
    }
}

class BoardPosition: ObservableObject {
    var width: Int
    var height: Int
    var board: [[PointState]]
    var nextToMove: StoneColor
    var previousPosition: BoardPosition?
    var lastMove: Move?
    var captures: [StoneColor: Int] = [.black: 0, .white: 0]
    @Published var removedStones: Set<[Int]>?
    @Published var gameScores: GameScores?
    @Published var estimatedScores: [[PointState]]?
    var lastMoveNumber = 0
    
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
        self.captures = previousPosition.captures
        self.lastMoveNumber = previousPosition.lastMoveNumber + 1
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
    
    func neighbors(of point: [Int]) -> Set<[Int]> {
        return self.neighbors(row: point[0], column: point[1])
    }
    
    func groupWithSameState(atRow row: Int, column: Int) -> Set<[Int]> {
        var result = Set<[Int]>([[row, column]])
        var currentPoints = Set<[Int]>([[row, column]])
        while currentPoints.count > 0 {
            var nextPoints = Set<[Int]>()
            for point in currentPoints {
                for neighbor in neighbors(of: point).filter({ self[$0] == self[point] }) {
                    if !result.contains(neighbor) {
                        result.insert(neighbor)
                        nextPoints.insert(neighbor)
                    }
                }
            }
            currentPoints = nextPoints
        }
        return result
    }
    
    func stoneGroup(atRow row: Int, column: Int) -> Set<[Int]> {
        guard case .hasStone = self[row, column] else {
            return []
        }
        
        return groupWithSameState(atRow: row, column: column)
    }
    
    func stoneGroup(at point: [Int]) -> Set<[Int]> {
        return self.stoneGroup(atRow: point[0], column: point[1])
    }
    
    func liberties(group: Set<[Int]>) -> Set<[Int]> {
        var liberties = Set<[Int]>()
        for point in group {
            for neighbor in self.neighbors(of: point) {
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
    
    func makeHandicapPlacement(move: Move) throws -> BoardPosition {
        switch move {
        case .pass:
            throw MoveError.unexpectedInvalidMove
        case .placeStone(let row, let column):
            if case .hasStone = self[row, column] {
                throw MoveError.pointAlreadyOccupied
            }
            let newPosition = BoardPosition(fromPreviousPosition: self, lastMove: move)
            newPosition.nextToMove = self.nextToMove
            newPosition[row, column] = .hasStone(self.nextToMove)
            return newPosition
        }
    }
    
    func makeMove(move: Move, allowsSelfCapture: Bool = false) throws -> BoardPosition {
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
                        let neighborGroup = newPosition.stoneGroup(at: neighbor)
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
                let groupWithNewMove = newPosition.stoneGroup(atRow: row, column: column)
                if newPosition.liberties(group: groupWithNewMove).count == 0 {
                    if !allowsSelfCapture {
                        throw MoveError.suicidalMove
                    } else {
                        newPosition.captureGroup(group: groupWithNewMove)
                    }
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
    
    static func positionString(fromPoints points: Set<[Int]>) -> String {
        var result = ""
        let sortedPoints = points.sorted {
            return $0[0] < $1[0] || ($0[0] == $1[0] && $0[1] < $1[1])
        }
        for point in sortedPoints {
            let row = point[0]
            let column = point[1]
            result += "\(coordinateLabels[column])\(coordinateLabels[row])"
        }
        return result
    }
    
    func estimateTerritory(on queue: DispatchQueue?) -> AnyPublisher<[[PointState]], Never> {
        return Future<[[PointState]], Never> { [self] promise in
            let queue = queue ?? DispatchQueue.global()
            queue.async { [self] in
                var data = board.joined().map({ state -> CInt in
                    switch state {
                    case .empty:
                        return 0
                    case .hasStone(let color):
                        return color == .white ? -1 : 1
                    }
                })
                se_estimate(CInt(width), CInt(height), &data, nextToMove == .white ? -1 : 1, 1000, Float(0.3))
                
                var estimatedTerritory = Array(repeating: Array(repeating: PointState.empty, count: width), count: height)
                for i in 0..<height * width {
                    let row = i / width
                    let column = i % width
                    if data[i] == 0 {
                        estimatedTerritory[row][column] = .empty
                    } else if data[i] == -1 {
                        estimatedTerritory[row][column] = .hasStone(.white)
                    } else {
                        estimatedTerritory[row][column] = .hasStone(.black)
                    }
                }
                promise(.success(estimatedTerritory))
            }
        }.eraseToAnyPublisher()
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
    
    private var _territoryGroupId: [[Int]] = []
    private var _currentTerritoryId = 0
    private var _territoryGroupById = [Int: TerritoryGroup]()
    private func _territoryGroup(atRow row: Int, column: Int) -> TerritoryGroup? {
        return _territoryGroupById[_territoryGroupId[row][column]]
    }
    
    private func _constructTerritoryGroupFromPoint(row: Int, column: Int, state: PointState, isDame: Bool) -> TerritoryGroup {
        var pointsForGroup = Set([[row, column]])
        var currentPoints = Set(pointsForGroup)
        let isRemoved: ([Int]) -> Bool = { self.removedStones?.contains($0) ?? false }
        var groupCondition: ([Int]) -> Bool =
            {
                // Dame group
                self[$0] == .empty && isRemoved($0)
            }
            
        if !isDame {
            groupCondition = {
                if isRemoved($0) {
                    if self[$0] == .empty {
                        // a dame point
                        return false
                    }
                    return state == .empty
                } else {
                    return self[$0] == state
                }
            }
        }
        while currentPoints.count > 0 {
            var nextPoints = Set<[Int]>()
            for point in currentPoints {
                for neighbor in neighbors(of: point) {
                    if groupCondition(neighbor) {
                        if _territoryGroupId[neighbor[0]][neighbor[1]] == 0 {
                            _territoryGroupId[neighbor[0]][neighbor[1]] = _currentTerritoryId
                            nextPoints.insert(neighbor)
                            pointsForGroup.insert(neighbor)
                        }
                    }
                }
            }
            currentPoints = nextPoints
        }
        let group = TerritoryGroup(points: pointsForGroup, state: state, isDame: isDame)
        return group
    }
    
    func constructTerritoryGroups() -> [TerritoryGroup] {
        _territoryGroupId = Array(repeating: Array(repeating: 0, count: self.width), count: self.height)
        _currentTerritoryId = 0
        var groups = [TerritoryGroup]()
        _territoryGroupById = [Int: TerritoryGroup]()
        for row in 0..<height {
            for column in 0..<width {
                if _territoryGroupId[row][column] == 0 {
                    _currentTerritoryId += 1
                    _territoryGroupId[row][column] = _currentTerritoryId
                    let isRemoved = self.removedStones?.contains([row, column]) ?? false
                    let newGroup = _constructTerritoryGroupFromPoint(row: row, column: column, state: isRemoved ? .empty : self[row, column], isDame: isRemoved && self[row, column] == .empty)
                    groups.append(newGroup)
                    _territoryGroupById[_currentTerritoryId] = newGroup
                }
            }
        }
        for group in groups {
            for point in group.points {
                for neighbor in neighbors(of: point) {
                    let neighborGroupId = _territoryGroupId[neighbor[0]][neighbor[1]]
                    group.neighbors.insert(_territoryGroupById[neighborGroupId]!)
                }
            }
        }
        for row in 0..<height {
            print(_territoryGroupId[row])
        }
        return groups
    }
    
    func groupForStoneRemoval(atRow row: Int, column: Int) -> Set<[Int]> {
        let isInitialPointRemoved = removedStones?.contains([row, column]) ?? false
        if self[row, column] == .empty {
            return groupWithSameState(atRow: row, column: column).filter({
                let isRemoved = self.removedStones?.contains($0) ?? false
                return isRemoved == isInitialPointRemoved
            })
        } else {
            var result = Set<[Int]>([[row, column]])
            var visited = Set<[Int]>(result)
            let initialPointState = self[row, column]
            var currentPoints = Set<[Int]>(result)
            while currentPoints.count > 0 {
                var nextPoints = Set<[Int]>()
                for point in currentPoints {
                    for neighbor in neighbors(of: point) {
                        let isNeighborEmpty = self[neighbor] == .empty
                        let isNeighborRemoved = removedStones?.contains(neighbor) ?? false
                        let isNeighborInSameState = self[neighbor] == initialPointState
                        if isNeighborEmpty || (isNeighborInSameState && (isNeighborRemoved == isInitialPointRemoved)) {
                            if !visited.contains(neighbor) {
                                visited.insert(neighbor)
                                nextPoints.insert(neighbor)
                                if !isNeighborEmpty {
                                    result.insert(neighbor)
                                }
                            }
                        }
                    }
                }
                currentPoints = nextPoints
            }
            
            return result
        }
    }
}
