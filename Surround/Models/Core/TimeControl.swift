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

enum TimeControlSpeed: String, Codable {
    case live
    case correspondence
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
        var speed: TimeControlSpeed?
        var pauseOnWeekends: Bool?
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
    
    var shortDescription: String {
        switch system {
        case .Fischer(let initialTime, let timeIncrement, let maxTime):
            return "\(durationString(seconds: initialTime)) + \(durationString(seconds: timeIncrement)) up to \(durationString(seconds: maxTime))"
        case .Simple(let perMove):
            return "\(durationString(seconds: perMove))/move"
        case .ByoYomi(let mainTime, let periods, let periodTime):
            return "\(durationString(seconds: mainTime)) + \(periods) × \(durationString(seconds: periodTime))"
        case .Canadian(let mainTime, let periodTime, let stonesPerPeriod):
            return "\(durationString(seconds: mainTime)) + \(durationString(seconds: periodTime))/\(stonesPerPeriod)"
        case .Absolute(let totalTime):
            return durationString(seconds: totalTime)
        case .None:
            return "No time limits"
        }
    }
    
    var systemName: String {
        switch system {
        case .Fischer:
            return "Fischer"
        case .ByoYomi:
            return "Japanese Byo-Yomi"
        case .Canadian:
            return "Canadian Byo-Yomi"
        case .Absolute:
            return "Absolute"
        case .Simple:
            return "Simple"
        case .None:
            return "None"
        }
    }

    private func durationString(seconds: Int) -> String {
        var secondsLeft = seconds
        let weeks = secondsLeft / (86400 * 7)
        secondsLeft %= 86400 * 7
        let days = secondsLeft / 86400
        secondsLeft %= 86400
        let hours = secondsLeft / 3600
        secondsLeft %= 3600
        let minutes = secondsLeft / 60
        secondsLeft %= 60
        var result = ""
        if weeks > 0 {
            result += "\(weeks) week\(weeks == 1 ? "" : "s")"
        }
        if days > 0 {
            result += " \(days) day\(days == 1 ? "" : "s")"
        }
        if hours > 0 {
            result += " \(hours) hour\(hours == 1 ? "" : "s")"
        }
        if minutes > 0 {
            result += " \(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        if secondsLeft > 0 {
            result += " \(secondsLeft) seconds\(secondsLeft == 1 ? "" : "s")"
        }

        return result.trimmingCharacters(in: .whitespaces)
    }
}
