//
//  OGSChatMessage.swift
//  Surround
//
//  Created by Anh Khoa Hong on 11/02/2022.
//

import Foundation

struct OGSChatMessageContent: Codable, Equatable {
    var id: String
    var message: String
    var timestamp: Double
    
    enum CodingKeys: String, CodingKey {
        case id = "i"
        case message = "m"
        case timestamp = "t"
    }
    
    static var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .none
        formatter.dateStyle = .medium
        return formatter
    }()
    
    var dateString: String {
//        return "xx \(Date(timeIntervalSince1970: timestamp))"
        return OGSPrivateMessageContent.dateFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}

struct OGSChatMessage: Decodable {
    var channel: String?
    var from: OGSUser?
    var content: OGSChatMessageContent
    
    enum CodingKeys: String, CodingKey {
        case channel
        case message
        case username
        case id
        case ranking
        case professional
        case uiClass
        case country
        case ratings
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let username = try? container.decodeIfPresent(String.self, forKey: .username)
        let id = try? container.decodeIfPresent(Int.self, forKey: .id)
        let ranking = try? container.decodeIfPresent(Double.self, forKey: .ranking)
        let professional = try? container.decodeIfPresent(Bool.self, forKey: .professional)
        let ratings = try? container.decodeIfPresent(OGSRating.self, forKey: .ratings)
        let uiClass = try? container.decodeIfPresent(String.self, forKey: .uiClass)
        let country = try? container.decodeIfPresent(String.self, forKey: .country)
        if let username = username, let id = id {
            self.from = OGSUser(username: username, id: id, ranking: ranking, uiClass: uiClass, country: country, professional: professional, ratings: ratings)
        }
        self.channel = try container.decodeIfPresent(String.self, forKey: .channel)
        self.content = try container.decode(OGSChatMessageContent.self, forKey: .message)
    }
}
