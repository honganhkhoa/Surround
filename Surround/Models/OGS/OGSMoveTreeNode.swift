//
//  OGSMoveTreeNode.swift
//  Surround
//
//  Created by Anh Khoa Hong on 29/05/2021.
//

import Foundation

struct OGSMoveTreeNode {
    var branches: [OGSMoveTreeNode] = []
    var move: Move?
    var trunk = false
    var position: BoardPosition?
    
}

extension OGSMoveTreeNode: Decodable {
    enum CodingKeys: String, CodingKey {
        case branches
        case x
        case y
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let row = try? container.decodeIfPresent(Int.self, forKey: .x),
           let column = try? container.decodeIfPresent(Int.self, forKey: .y) {
            if row == -1 {
                move = .pass
            } else {
                move = .placeStone(row, column)
            }
        }
        
        branches = try container.decodeIfPresent([OGSMoveTreeNode].self, forKey: .branches) ?? []
    }
}
