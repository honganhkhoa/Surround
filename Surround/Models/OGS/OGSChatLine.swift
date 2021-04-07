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
        // TODO: This is a quick fix for an arithmetic overflow crash that cannot be caught, will handle this case properly when implementing support for board markers.
        if !moveString.contains("!") {
            moves = Move.fromMoveString(moveString: moveString)
        } else {
            moves = []
        }
        name = try container.decode(String.self, forKey: .name)
    }
}

struct OGSChatLine: Decodable, Identifiable, Hashable {
    var id: String
    var channel: OGSChatChannel
    var timestamp: Date
    var moveNumber: Int
    var body: String
    var user: OGSUser
    var variationData: OGSChatLineVariation?
    var variation: Variation?
    
    struct OGSChatLineCodingData: Decodable, Hashable {
        var body: String
        var chatId: String
        var date: Double
        var moveNumber: Int
        var playerId: Int
        var professional: Bool
        var ranking: Double
        var ratings: OGSRating?
        var uiClass: String
        var username: String
        var variation: OGSChatLineVariation?
        
        enum CodingKeys: String, CodingKey {
            case body, chatId, date, moveNumber, playerId, professional, ranking, ratings, uiClass, username
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
            ranking = try container.decode(Double.self, forKey: .ranking)
            ratings = try container.decodeIfPresent(OGSRating.self, forKey: .ratings)
            uiClass = try container.decode(String.self, forKey: .uiClass)
            username = try container.decode(String.self, forKey: .username)
        }

        static func == (lhs: OGSChatLine.OGSChatLineCodingData, rhs: OGSChatLine.OGSChatLineCodingData) -> Bool {
            return lhs.chatId == rhs.chatId
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(chatId)
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
        id = codingData.line.chatId
        timestamp = Date(timeIntervalSince1970: codingData.line.date)
        moveNumber = codingData.line.moveNumber
        body = codingData.line.body
        user = OGSUser(
            username: codingData.line.username,
            id: codingData.line.playerId,
            ranking: codingData.line.ranking,
            uiClass: codingData.line.uiClass,
            professional: codingData.line.professional,
            ratings: codingData.line.ratings
        )
        variationData = codingData.line.variation
    }

    static func == (lhs: OGSChatLine, rhs: OGSChatLine) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static var coordinatesRegex: NSRegularExpression {
        let regex = try! NSRegularExpression(pattern: #"\b[abcdefghjklmnopqrstuvwxyz]([1-9]|1[0-9]|2[0-5])\b"#, options: [.caseInsensitive])
        return regex
    }
    
    lazy var coordinatesInBody: [NSTextCheckingResult] = {
        OGSChatLine.coordinatesRegex.matches(
            in: self.body,
            options: [],
            range: NSRange(location: 0, length: self.body.utf16.count)
        )
    }()
    
    lazy var coordinatesRanges: [NSRange] = {
        self.coordinatesInBody.map { $0.range }
    }()
    
    lazy var coordinates: [[Int]] = {
        self.coordinatesRanges.map {
            var startIndex = self.body.index(self.body.startIndex, offsetBy: $0.location)
            let letter = self.body[startIndex].lowercased()
            let endIndex = self.body.index(startIndex, offsetBy: $0.length)
            startIndex = self.body.index(startIndex, offsetBy: 1)
            let number = Int(self.body[startIndex..<endIndex])!
            let column = Int(letter.first!.asciiValue! - "a".first!.asciiValue!)
            return [number - 1, column > 8 ? column - 1 : column]
        }
    }()
}
