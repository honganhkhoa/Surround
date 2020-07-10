//
//  OGSActiveGames.swift
//  Surround
//
//  Created by Anh Khoa Hong on 7/10/20.
//

import Foundation

class OGSActiveGames: ObservableObject {
    @Published var activeGames = [Int: Game]()
    var gameList: [Game] {
        return Array(activeGames.values)
    }
    
    subscript(gameId: Int) -> Game? {
        get {
            return self.activeGames[gameId]
        }
        set {
            self.activeGames[gameId] = newValue
        }
    }
}
