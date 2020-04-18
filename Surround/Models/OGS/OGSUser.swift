//
//  OGSUser.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/24/20.
//

import Foundation

struct OGSUser : Codable {
    var username: String
    var id: Int
    var ranking: Int?
    var rank: Double?
    var uiClass: String?
    var isTournamentModerator: Bool?
    var canCreateTournaments: Bool?
    var country: String?
    var professional: Bool?
    var provisional: Int?
    var icon: String?
    var supporter: Bool?
}
