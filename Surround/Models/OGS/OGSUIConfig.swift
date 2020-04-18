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
}
