//
//  OGSPuzzle.swift
//  Surround
//
//  Created by Anh Khoa Hong on 29/05/2021.
//

import Foundation

struct OGSPuzzle: Decodable {
    struct InitialState: Codable {
        var black: String
        var white: String
    }

    var height: Int
    var width: Int
    var initialPlayer: StoneColor
    var initialState: InitialState
    var moveTree: OGSMoveTreeNode
    
    var name: String
    var puzzleCollection: String
    var puzzleDescription: String
}

struct OGSPuzzleInfo: Decodable {
    var height: Int
    var width: Int
    var owner: OGSUser
    var puzzle: OGSPuzzle
}
