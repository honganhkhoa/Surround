//
//  TimeControl.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/5/20.
//

import Foundation

enum TimeControlSystem {
    case Fischer(initialTime: Int, timeIncrement: Int, maxTime: Int)
    case ByoYomi(mainTime: Int, periods: Int, periodTime: Int)
    case Simple(perMove: Int)
    case Canadian(mainTime: Int, periodTime: Int, stonesPerPeriod: Int)
    case Absolute(totalTime: Int)
    case None
}

@dynamicMemberLookup
struct TimeControl: Codable {
    struct TimeControlCodingData: Codable {
        var timeControl: String
        var initialTime: Int?
        var timeIncrement: Int?
        var maxTime: Int?
        var mainTime: Int?
        var periods: Int?
        var periodTime: Int?
        var perMove: Int?
        var stonesPerPeriod: Int?
        var totalTime: Int?
        var speed: String?
        var pauseOnWeekend: Bool?
    }
    
    var codingData: TimeControlCodingData
    
    init(from decoder:Decoder) throws {
        let container = try decoder.singleValueContainer()
        codingData = try container.decode(TimeControlCodingData.self)
    }
    
    init(codingData: TimeControlCodingData) {
        self.codingData = codingData
    }
    
    subscript<T>(dynamicMember keyPath: KeyPath<TimeControlCodingData, T>) -> T {
        return self.codingData[keyPath: keyPath]
    }
    
    var system: TimeControlSystem {
        switch self.timeControl {
        case "fischer":
            return .Fischer(initialTime: self.initialTime!, timeIncrement: self.timeIncrement!, maxTime: self.maxTime!)
        case "byoyomi":
            return .ByoYomi(mainTime: self.mainTime!, periods: self.periods!, periodTime: self.periodTime!)
        case "simple":
            return .Simple(perMove: self.perMove!)
        case "canadian":
            return .Canadian(mainTime: self.mainTime!, periodTime: self.periodTime!, stonesPerPeriod: self.stonesPerPeriod!)
        case "absolute":
            return .Absolute(totalTime: self.totalTime!)
        default:
            return .None
        }
    }
}
