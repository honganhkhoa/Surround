//
//  OGSPauseControl.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/13/20.
//

import Foundation

struct OGSUserPauseDetail: Codable {
    var pausesLeft: Int?
    var pausingPlayerId: Int?
}

struct OGSModeratorPauseDetail: Codable {
    var moderatorId: Int?
}

struct OGSPauseControl: Decodable {
    var userPauseDetail: OGSUserPauseDetail?
    var moderatorPauseDetail: OGSModeratorPauseDetail?
    var weekend: Bool?
    var system: Bool?
    var stoneRemoval: Bool?
    var vacationPlayerIds: [Int] = []
    
    struct CodingKeys: CodingKey {
        var intValue: Int?
        var stringValue: String
        
        init? (stringValue: String) {
            self.stringValue = stringValue
        }
                
        init? (intValue: Int) {
            self.intValue = intValue
            self.stringValue = "\(intValue)"
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        for key in container.allKeys {
            switch key.stringValue {
            case let keyName where keyName.starts(with: "vacation-"):
                if let vacationPlayerId = Int(keyName[keyName.index(keyName.startIndex, offsetBy: 9)...]) {
                    vacationPlayerIds.append(vacationPlayerId)
                }
            case "paused":
                userPauseDetail = try container.decode(OGSUserPauseDetail.self, forKey: key)
            // OGS sends "moderator_paused" as an object; the decoder's snake-case
            // strategy surfaces it as "moderatorPaused", but accept the raw form too.
            case "moderatorPaused", "moderator_paused":
                moderatorPauseDetail = try container.decode(OGSModeratorPauseDetail.self, forKey: key)
            case "weekend":
                weekend = try container.decode(Bool.self, forKey: key)
            // Goban treats the legacy "server" pause the same as "system".
            case "system", "server":
                system = try container.decode(Bool.self, forKey: key)
            case "stone-removal":
                stoneRemoval = try container.decode(Bool.self, forKey: key)
            default:
                break
            }
        }
    }
    
    func isPaused() -> Bool {
        if self.userPauseDetail != nil {
            return true
        }

        if self.moderatorPauseDetail != nil {
            return true
        }

        if weekend ?? false {
            return true
        }

        if system ?? false {
            return true
        }

        if stoneRemoval ?? false {
            return true
        }

        if vacationPlayerIds.count > 0 {
            return true
        }

        return false
    }
    
    func pauseReason(playerId: Int?) -> String {
        guard self.isPaused() else {
            return ""
        }
        
        if let playerId = playerId {
            if let userPauseDetail = userPauseDetail {
                if userPauseDetail.pausingPlayerId == playerId {
                    return String(localized: "Paused, \(userPauseDetail.pausesLeft!) left", comment: "pause reason (pausing player is you)")
                } else {
                    return String(localized: "Paused", comment: "pause reason")
                }
            }
            if vacationPlayerIds.contains(playerId) {
                return String(localized: "Vacation", comment: "pause reason")
            }
        }

        if moderatorPauseDetail != nil {
            return String(localized: "Moderator", comment: "pause reason")
        }

        if weekend ?? false {
            return String(localized: "Weekend", comment: "pause reason")
        }
        
        if system ?? false {
            return String(localized: "System", comment: "pause reason")
        }
                
        if stoneRemoval ?? false {
            return String(localized: "Stone removal", comment: "pause reason")
        }
        
        return String(localized: "Paused")
    }
}
