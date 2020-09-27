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

struct OGSPauseControl: Decodable {
    var userPauseDetail: OGSUserPauseDetail?
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
            case "weekend":
                weekend = try container.decode(Bool.self, forKey: key)
            case "system":
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
                    return "Paused, \(userPauseDetail.pausesLeft!) left"
                } else {
                    return "Paused"
                }
            }
            if vacationPlayerIds.contains(playerId) {
                return "Vacation"
            }
        }

        if weekend ?? false {
            return "Weekend"
        }
        
        if system ?? false {
            return "System"
        }
                
        if stoneRemoval ?? false {
            return "Stone removal"
        }
        
        return "Paused"
    }
}
