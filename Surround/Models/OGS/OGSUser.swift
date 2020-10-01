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
    
    // In-game
    var acceptedStones: String?
    var acceptedStrickSekiMode: Bool?
    
    var formattedRank: String {
        let rank = self.rank ?? (self.ranking == nil ? nil : Double(self.ranking!))
        return formattedRankString(rank: rank, professional: professional ?? false)
    }
    
    func iconURL(ofSize size: Int) -> URL? {
        guard let icon = self.icon else {
            return nil
        }
        
        let regex1 = try! NSRegularExpression(pattern: "-[0-9]+.png")
        let regex2 = try! NSRegularExpression(pattern: "s=[0-9]+")
        var result = icon
        result = regex1.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: "-\(size).png")
        result = regex2.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: "s=\(size)")
        return URL(string: result)
    }
}

func formattedRankString(rank: Double?, professional: Bool = false) -> String {
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
