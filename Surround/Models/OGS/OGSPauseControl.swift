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
    var paused: OGSUserPauseDetail?
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
        print(container.allKeys)
    }
    
    func isPaused() -> Bool {
        if self.paused != nil {
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
}
