//
//  OGSUser.swift
//  Surround
//
//  Created by Anh Khoa Hong on 4/24/20.
//

import Foundation
import SwiftUI

struct OGSCategoryRating: Codable {
    var rating: Double
    var deviation: Double
    var volatility: Double
}

enum OGSRatingCategory: String, Codable, CodingKey, CaseIterable {
    case overall = "overall"
    case overall_9x9 = "9x9"
    case overall_19x19 = "19x19"
    case live_9x9 = "live-9x9"
    case live_19x19 = "live-19x19"
    case live_overall = "live"
    case blitz_9x9 = "blitz-9x9"
    case blitz_19x19 = "blitz-19x19"
    case blitz_overall = "blitz"
    case correspondence_9x9 = "correspondence-9x9"
    case correspondence_19x19 = "correspondence-19x19"
    case correspondence_overall = "correspondence"
}

struct OGSRating: Codable {
    var ratingByCategory: [OGSRatingCategory: OGSCategoryRating]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: OGSRatingCategory.self)
        
        ratingByCategory = [:]
        for category in OGSRatingCategory.allCases {
            if container.contains(category) {
                ratingByCategory[category] = try container.decode(OGSCategoryRating.self, forKey: category)
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: OGSRatingCategory.self)
        for category in ratingByCategory.keys {
            try container.encode(ratingByCategory[category], forKey: category)
        }
    }
    
    subscript(category: OGSRatingCategory) -> OGSCategoryRating? {
        get {
            return ratingByCategory[category]
        }
    }
}

struct OGSUser : Codable {
    var username: String
    var id: Int
    var ranking: Double?
    var rank: Double?
    var uiClass: String?
    var isTournamentModerator: Bool?
    var canCreateTournaments: Bool?
    var country: String?
    var professional: Bool?
    var provisional: Int?
    var icon: String?
    var supporter: Bool?
    var ratings: OGSRating?
    
    // In-game
    var acceptedStones: String?
    var acceptedStrickSekiMode: Bool?
    
    var formattedRank: String {
        return self.formattedRank()
    }
    
    var uiColor: Color {
        if uiClass?.contains("moderator") == true {
            return .purple
        } else if uiClass?.contains("professional") == true {
            return .green
        } else if uiClass?.contains("supporter") == true {
            return .orange
        }
        return .blue
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
    
    private static let defaultRating = OGSCategoryRating(rating: 1500, deviation: 350, volatility: 0.06)
    private static let provisionalDeviationThreshold = 160.0

    func rank(category: OGSRatingCategory = .overall) -> Double {
        let ratings = self.ratings?[category] ?? OGSUser.defaultRating
        
        return floor(RankUtils.rank(fromRating: ratings.rating))
    }
    
    func formattedRank(category: OGSRatingCategory = .overall, longFormat: Bool = false) -> String {
        let explicitRank: Double? = self.ranking != nil ? Double(self.ranking!) : self.rank
        if self.professional == true {
            if let ranking = explicitRank {
                return RankUtils.formattedRank(ranking, professional: true)
            }
        }
        
        if self.isProvisional() {
            return "?"
        }

        if let ranking = self.ratings != nil ? self.rank() : explicitRank {
            return RankUtils.formattedRank(ranking)
        }
        
        return "?"
    }
    
    func isProvisional() -> Bool {
        if uiClass?.contains("provisional") == true {
            return true
        }
        if let rating = self.ratings?[.overall] {
            return rating.deviation >= OGSUser.provisionalDeviationThreshold
        }
        return false
    }
    
    static func mergeUserInfoFromCache(user: OGSUser?, cachedUser: OGSUser) -> OGSUser {
        guard var user = user else {
            return cachedUser
        }
        
        if user.ratings == nil && cachedUser.ratings != nil {
            user.ratings = cachedUser.ratings
        }
        
        if user.icon == nil && cachedUser.icon != nil {
            user.icon = cachedUser.icon
        }
        
        return user
    }
}

struct RankUtils {
    private static let minRank = 5.0
    private static let maxRank = 38.0
    
    private static let minRating = 100.0
    private static let maxRating = 6000.0
    private static let A = 525.0
    private static let C = 23.15
    
    static func rating(fromRank rank: Double) -> Double {
        return A * exp(rank / C)
    }
    
    static func rank(fromRating rating: Double) -> Double {
        return log(min(maxRating, max(minRating, rating)) / A) * C
    }
    
    static func formattedRank(_ ranking: Double, longFormat: Bool = false, professional: Bool = false) -> String {
        if professional {
            if ranking > 900 {
                return "\(Int((ranking - 1000) - 36))p"
            } else {
                return "\(Int(ranking - 36))p"
            }
        } else {
            if ranking > 900 {
                return "\(Int((ranking - 1000) - 36))p"
            }
            if ranking < -900 {
                return "?"
            }
            
            let boundedRank = max(minRank, min(ranking, maxRank))
            if boundedRank < 30 {
                return "\(Int(ceil(30 - boundedRank)))\(longFormat ? " Kyu" : "k")"
            } else {
                return "\(Int(floor(boundedRank - 29)))\(longFormat ? " Dan" : "d")"
            }
        }
    }
}
