//
//  Game.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/30/20.
//

import Foundation

enum GameID {
    case OGS(Int)
}

class Game: ObservableObject, Identifiable {
    @Published var gameData: OGSGame? {
        didSet {
            if let data = gameData {
                self.blackRank = data.players.black.rank
                self.whiteRank = data.players.white.rank
                var position = initialPosition
                do {
                    var firstMoveIndex = 0
                    var initialPositionStones = 0
                    if data.initialState.white.count > 0 || data.initialState.black.count > 0 {
                        for point in BoardPosition.points(fromPositionString: data.initialState.black) {
                            position.putStone(row: point[0], column: point[1], color: .black)
                            initialPositionStones += 1
                        }
                        for point in BoardPosition.points(fromPositionString: data.initialState.white) {
                            position.putStone(row: point[0], column: point[1], color: .white)
                            initialPositionStones += 1
                        }
                    }
                    if data.handicap > 0 {
                        if data.moves.count >= data.handicap && initialPositionStones == 0 {
                            for handicapMove in data.moves[..<data.handicap] {
                                position.putStone(row: handicapMove[1], column: handicapMove[0], color: .black)
                            }
                            firstMoveIndex = data.handicap
                        }
                    }
                    position.nextToMove = data.initialPlayer
                    for move in data.moves[firstMoveIndex...] {
                        position = try position.makeMove(move: move[0] == -1 ? .pass : .placeStone(move[1], move[0]))
                    }
                } catch {
                    print(error)
                }
                currentPosition = position
                if let removedStones = gameData?.removed {
                    currentPosition.removedStones = BoardPosition.points(fromPositionString: removedStones)
                }
                currentPosition.gameScores = gameData?.score
                clock = data.clock
                
                if data.outcome != nil {
                    OGSWebSocket.shared.disconnect(from: self)
                }
            }
        }
    }
    var boardSize: Int
    var blackName: String
    var whiteName: String
    @Published var blackRank: Double?
    @Published var whiteRank: Double?
    @Published var gameName: String?
    @Published var currentPosition: BoardPosition
    var blackFormattedRank: String {
        return formattedRank(rank: blackRank, professional: gameData?.players.black.professional ?? false)
    }
    var whiteFormattedRank: String {
        return formattedRank(rank: whiteRank, professional: gameData?.players.white.professional ?? false)
    }
    var initialPosition: BoardPosition
    var ID: GameID
    var ogsRawData: [String: Any]?
    @Published var clock: Clock?
    
    init(boardSize: Int, blackName: String, whiteName: String, gameId: GameID) {
        self.boardSize = boardSize
        self.blackName = blackName
        self.whiteName = whiteName
        self.ID = gameId
        self.initialPosition = BoardPosition(boardSize: boardSize)
        self.currentPosition = self.initialPosition
    }
    
    init(ogsGame: OGSGame) {
        self.boardSize = ogsGame.width
        self.blackName = ogsGame.players.black.username
        self.whiteName = ogsGame.players.white.username
        self.ID = .OGS(ogsGame.gameId)
        self.initialPosition = BoardPosition(boardSize: boardSize)
        self.currentPosition = self.initialPosition
        self.gameData = ogsGame
    }
    
    func makeMove(move: Move) throws {
        self.currentPosition = try currentPosition.makeMove(move: move)
    }
    
    private func formattedRank(rank: Double?, professional: Bool = false) -> String {
        guard let rawRank = rank else {
            return "?"
        }
        let displayedRank = Int(floor(rawRank))
        if professional {
            return "\(max(displayedRank - 36, 1))p"
        } else {
            if displayedRank >= 30 {
                return "\(min(displayedRank - 30 + 1, 9))d"
            } else {
                return "\(30 - displayedRank)k"
            }
        }
    }
}
