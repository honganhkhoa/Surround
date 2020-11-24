//
//  OGSChatLine.swift
//  Surround
//
//  Created by Anh Khoa Hong on 16/11/2020.
//

import Foundation

enum OGSChatChannel: String, Codable {
    case main
    case malkovich
    case spectator
}

struct OGSChatLineVariation: Decodable {
    var fromMoveNumber: Int
    var moves: [Move]
    var name: String
    
    enum CodingKeys: String, CodingKey {
        case from
        case moves
        case name
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: OGSChatLineVariation.CodingKeys.self)
        
        fromMoveNumber = try container.decode(Int.self, forKey: .from)
        let moveString = try container.decode(String.self, forKey: .moves)
        moves = Move.fromMoveString(moveString: moveString)
        name = try container.decode(String.self, forKey: .name)
    }
}

struct OGSChatLine: Decodable {
    var channel: OGSChatChannel
    var chatId: String
    var timestamp: Date
    var moveNumber: Int
    var body: String
    var user: OGSUser
    var variation: OGSChatLineVariation?
    
    struct OGSChatLineCodingData: Decodable {
        var body: String
        var chatId: String
        var date: Double
        var moveNumber: Int
        var playerId: Int
        var professional: Bool
        var ranking: Int
        var uiClass: String
        var username: String
        var variation: OGSChatLineVariation?
        
        enum CodingKeys: String, CodingKey {
            case body, chatId, date, moveNumber, playerId, professional, ranking, uiClass, username
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: OGSChatLineCodingData.CodingKeys.self)
            if let variation = try? container.decode(OGSChatLineVariation.self, forKey: .body) {
                self.body = variation.name
                self.variation = variation
            } else {
                body = try container.decode(String.self, forKey: .body)
            }
            chatId = try container.decode(String.self, forKey: .chatId)
            date = try container.decode(Double.self, forKey: .date)
            moveNumber = try container.decode(Int.self, forKey: .moveNumber)
            playerId = try container.decode(Int.self, forKey: .playerId)
            professional = try container.decode(Bool.self, forKey: .professional)
            ranking = try container.decode(Int.self, forKey: .ranking)
            uiClass = try container.decode(String.self, forKey: .uiClass)
            username = try container.decode(String.self, forKey: .username)
        }
    }
    
    struct OGSChatCodingData: Decodable {
        var channel: OGSChatChannel
        var line: OGSChatLineCodingData
    }
    
    var codingData: OGSChatCodingData
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        codingData = try container.decode(OGSChatCodingData.self)
        
        channel = codingData.channel
        chatId = codingData.line.chatId
        timestamp = Date(timeIntervalSince1970: codingData.line.date)
        moveNumber = codingData.line.moveNumber
        body = codingData.line.body
        user = OGSUser(
            username: codingData.line.username,
            id: codingData.line.playerId,
            ranking: codingData.line.ranking,
            uiClass: codingData.line.uiClass,
            professional: codingData.line.professional
        )
    }
}
