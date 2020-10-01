//
//  OGSUIConfig.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/24/20.
//

import Foundation

struct OGSUIConfig: Codable {
    var csrfToken: String?
    var chatAuth: String?
    var incidentAuth: String?
    var notificationAuth: String?
    var userJwt: String?
    var user: OGSUser
    
    enum CodingKeys: String, CodingKey {
        case csrfToken
        case chatAuth
        case incidentAuth
        case notificationAuth
        case userJwt
        case user
        case error
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: OGSUIConfig.CodingKeys.self)
        
        if let error = try container.decodeIfPresent([String].self, forKey: .error) {
            throw OGSServiceError.loginError(error: error[0])
        }
        
        csrfToken = try container.decodeIfPresent(String.self, forKey: .csrfToken)
        chatAuth = try container.decodeIfPresent(String.self, forKey: .chatAuth)
        incidentAuth = try container.decodeIfPresent(String.self, forKey: .incidentAuth)
        notificationAuth = try container.decodeIfPresent(String.self, forKey: .notificationAuth)
        userJwt = try container.decodeIfPresent(String.self, forKey: .userJwt)
        user = try container.decode(OGSUser.self, forKey: .user)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: OGSUIConfig.CodingKeys.self)
        
        try container.encodeIfPresent(csrfToken, forKey: .csrfToken)
        try container.encodeIfPresent(chatAuth, forKey: .chatAuth)
        try container.encodeIfPresent(incidentAuth, forKey: .incidentAuth)
        try container.encodeIfPresent(notificationAuth, forKey: .notificationAuth)
        try container.encodeIfPresent(userJwt, forKey: .userJwt)
        try container.encodeIfPresent(user, forKey: .user)
    }
}
