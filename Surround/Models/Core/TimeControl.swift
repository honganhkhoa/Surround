//
//  TimeControl.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/5/20.
//

import Foundation
import SwiftUI

func durationString(seconds: Int, longFormat: Bool = false) -> String {
    if seconds == 0 {
        return longFormat ? "None" : ""
    }
    
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
        result += "\(weeks)" + (longFormat ? " week\(weeks == 1 ? "" : "s")" : "w")
    }
    if days > 0 {
        result += " \(days)" + (longFormat ? " day\(days == 1 ? "" : "s")" : "d")
    }
    if hours > 0 {
        result += " \(hours)" + (longFormat ? " hour\(hours == 1 ? "" : "s")" : "h")
    }
    if minutes > 0 {
        result += " \(minutes)" + (longFormat ? " minute\(minutes == 1 ? "" : "s")" : "m")
    }
    if secondsLeft > 0 {
        result += " \(secondsLeft)" + (longFormat ? " second\(secondsLeft == 1 ? "" : "s")" : "s")
    }

    return result.trimmingCharacters(in: .whitespaces)
}

enum TimeControlSystem: Equatable {
    case Fischer(initialTime: Int, timeIncrement: Int, maxTime: Int)
    case ByoYomi(mainTime: Int, periods: Int, periodTime: Int)
    case Simple(perMove: Int)
    case Canadian(mainTime: Int, periodTime: Int, stonesPerPeriod: Int)
    case Absolute(totalTime: Int)
    case None
    
    var name: String {
        switch self {
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
    
    var shortName: String {
        switch self {
        case .Fischer:
            return "Fischer"
        case .ByoYomi:
            return "Byo-Yomi"
        case .Canadian:
            return "Canadian"
        case .Absolute:
            return "Absolute"
        case .Simple:
            return "Simple"
        case .None:
            return "None"
        }
    }
    
    var shortDescription: String {
        switch self {
        case .Fischer(let initialTime, let timeIncrement, let maxTime):
            return "\(durationString(seconds: initialTime)) + \(durationString(seconds: timeIncrement)) up to \(durationString(seconds: maxTime))"
        case .Simple(let perMove):
            return "\(durationString(seconds: perMove))/move"
        case .ByoYomi(let mainTime, let periods, let periodTime):
            return "\(durationString(seconds: mainTime))\(mainTime > 0 ? " + " : "")\(periods)×\(durationString(seconds: periodTime))"
        case .Canadian(let mainTime, let periodTime, let stonesPerPeriod):
            return "\(durationString(seconds: mainTime))\(mainTime > 0 ? " + " : "")\(durationString(seconds: periodTime))/\(stonesPerPeriod)"
        case .Absolute(let totalTime):
            return durationString(seconds: totalTime)
        case .None:
            return "No time limits"
        }
    }
    
    var descriptionText: Text {
        switch self {
        case .Fischer(let initialTime, let timeIncrement, let maxTime):
            return Text("Clock starts with ") + Text(durationString(seconds: initialTime, longFormat: true)).bold() +
                Text(" and increases by ") + Text(durationString(seconds: timeIncrement, longFormat: true)).bold() +
                Text(" per move, up to a maximum of ") + Text(durationString(seconds: maxTime, longFormat: true)).bold() + Text(".")
        case .Simple(let perMove):
            return Text(durationString(seconds: perMove, longFormat: true)).bold() + Text(" per move.")
        case .ByoYomi(let mainTime, let periods, let periodTime):
            if mainTime == 0 {
                return Text("\(periods) period\(periods == 1 ? "" : "s") of ") + Text(durationString(seconds: periodTime, longFormat: true)).bold() + Text(".")
            }
            return Text("Clock starts with ") + Text(durationString(seconds: mainTime, longFormat: true)).bold() +
                Text(" main time, follows by \(periods) period\(periods == 1 ? "" : "s") of ") + Text(durationString(seconds: periodTime, longFormat: true)).bold() + Text(".")
        case .Canadian(let mainTime, let periodTime, let stonesPerPeriod):
            if mainTime == 0 {
                return Text(durationString(seconds: periodTime, longFormat: true)).bold() + Text(" for every \(stonesPerPeriod) move\(stonesPerPeriod == 1 ? "" : "s").")
            }
            return Text("Clock starts with ") + Text(durationString(seconds: mainTime, longFormat: true)) +
                Text(" main time, follows by ") + Text(durationString(seconds: periodTime, longFormat: true)).bold() + Text(" for every \(stonesPerPeriod) move\(stonesPerPeriod == 1 ? "" : "s").")
        case .Absolute(let totalTime):
            return Text(durationString(seconds: totalTime, longFormat: true)).bold() + Text(" of total play time for each player.")
        case .None:
            return Text("No time limits.")
        }
    }
    
    var averageSecondsPerMove: Double {
        switch self {
        case .Fischer(let initialTime, let timeIncrement, _):
            return Double(initialTime) / 90.0 + Double(timeIncrement)
        case .ByoYomi(let mainTime, _, let periodTime):
            return Double(mainTime) / 90.0 + Double(periodTime)
        case .Simple(let perMove):
            return Double(perMove)
        case .Canadian(let mainTime, let periodTime, let stonesPerPeriod):
            return Double(mainTime) / 90.0 + Double(periodTime) / Double(stonesPerPeriod)
        case .Absolute(let totalTime):
            return Double(totalTime) / 90.0
        case .None:
            return 0
        }
    }

    var speed: TimeControlSpeed {
        let secondsPerMove = self.averageSecondsPerMove
        if secondsPerMove < 10 {
            return .blitz
        } else if secondsPerMove <= 3600 {
            return .live
        } else {
            return .correspondence
        }
    }

    var timeControlObject: TimeControl {
        switch self {
        case .Fischer(let initialTime, let timeIncrement, let maxTime):
            return TimeControl(codingData: TimeControl.TimeControlCodingData(
                timeControl: "fischer",
                initialTime: initialTime, timeIncrement: timeIncrement, maxTime: maxTime, speed: speed
            ))
        case .Simple(let perMove):
            return TimeControl(codingData: TimeControl.TimeControlCodingData(
                timeControl: "simple", perMove: perMove, speed: speed
            ))
        case .ByoYomi(let mainTime, let periods, let periodTime):
            return TimeControl(codingData: TimeControl.TimeControlCodingData(
                timeControl: "byoyomi", mainTime: mainTime, periods: periods, periodTime: periodTime, speed: speed
            ))
        case .Canadian(let mainTime, let periodTime, let stonesPerPeriod):
            return TimeControl(codingData: TimeControl.TimeControlCodingData(
                timeControl: "canadian", mainTime: mainTime, periodTime: periodTime, stonesPerPeriod: stonesPerPeriod, speed: speed
            ))
        case .Absolute(let totalTime):
            return TimeControl(codingData: TimeControl.TimeControlCodingData(
                timeControl: "absolute", totalTime: totalTime, speed: speed
            ))
        case .None:
            return TimeControl(codingData: TimeControl.TimeControlCodingData(
                timeControl: "none"
            ))
        }
    }

    static let QuestionableSecondsPerMove = 4
    static let QuestionableAbsoluteTime = 900
    
    var isUnusual: Bool {
        switch self {
        case .Fischer(let initialTime, let timeIncrement, _):
            return !(initialTime > TimeControlSystem.QuestionableAbsoluteTime || timeIncrement > TimeControlSystem.QuestionableSecondsPerMove)
        case .Simple(let perMove):
            return perMove < TimeControlSystem.QuestionableSecondsPerMove
        case .ByoYomi(let mainTime, _, let periodTime):
            return !(mainTime > TimeControlSystem.QuestionableAbsoluteTime || periodTime > TimeControlSystem.QuestionableSecondsPerMove)
        case .Canadian(let mainTime, let periodTime, let stonesPerPeriod):
            return !(mainTime > TimeControlSystem.QuestionableAbsoluteTime || periodTime / stonesPerPeriod > TimeControlSystem.QuestionableSecondsPerMove)
        case .Absolute(let totalTime):
            return totalTime <= TimeControlSystem.QuestionableAbsoluteTime
        case .None:
            return false
        }
    }
}

enum TimeControlSpeed: String, Codable {
    case live
    case correspondence
    case blitz
    
    var defaultTimeOptions: [TimeControlSystem] {
        switch self {
        case .blitz:
            return [
                .ByoYomi(mainTime: 30, periods: 5, periodTime: 5),
                .Fischer(initialTime: 30, timeIncrement: 10, maxTime: 60),
                .Canadian(mainTime: 30, periodTime: 30, stonesPerPeriod: 5),
                .Simple(perMove: 5),
                .Absolute(totalTime: 300)
            ]
        case .live:
            return [
                .ByoYomi(mainTime: 10 * 60, periods: 5, periodTime: 30),
                .Fischer(initialTime: 120, timeIncrement: 30, maxTime: 300),
                .Canadian(mainTime: 10 * 60, periodTime: 180, stonesPerPeriod: 10),
                .Simple(perMove: 60),
                .Absolute(totalTime: 900)
            ]
        case .correspondence:
            return [
                .Fischer(initialTime: 3 * 86400, timeIncrement: 86400, maxTime: 7 * 86400),
                .ByoYomi(mainTime: 7 * 86400, periods: 5, periodTime: 86400),
                .Canadian(mainTime: 7 * 86400, periodTime: 7 * 86400, stonesPerPeriod: 10),
                .Simple(perMove: 2 * 86400),
                .Absolute(totalTime: 28 * 86400),
                .None
            ]
        }
    }
}

@dynamicMemberLookup
struct TimeControl: Codable, Equatable {
    struct TimeControlCodingData: Codable, Equatable {
        internal init(timeControl: String, system: String? = nil, initialTime: Int? = nil, timeIncrement: Int? = nil, maxTime: Int? = nil, mainTime: Int? = nil, periods: Int? = nil, periodTime: Int? = nil, perMove: Int? = nil, stonesPerPeriod: Int? = nil, totalTime: Int? = nil, speed: TimeControlSpeed? = nil, pauseOnWeekends: Bool? = nil) {
            self.timeControl = timeControl
            self.system = timeControl
            self.initialTime = initialTime
            self.timeIncrement = timeIncrement
            self.maxTime = maxTime
            self.mainTime = mainTime
            self.periods = periods
            self.periodTime = periodTime
            self.perMove = perMove
            self.stonesPerPeriod = stonesPerPeriod
            self.totalTime = totalTime
            self.speed = speed
            self.pauseOnWeekends = pauseOnWeekends
        }
        
        var timeControl: String
        var system: String?
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
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(codingData)
    }

    static func == (lhs: TimeControl, rhs: TimeControl) -> Bool {
        return lhs.codingData == rhs.codingData
    }

    subscript<T>(dynamicMember keyPath: WritableKeyPath<TimeControlCodingData, T>) -> T {
        get { self.codingData[keyPath: keyPath] }
        set { self.codingData[keyPath: keyPath] = newValue }
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
        return system.shortDescription
    }
    
    var systemName: String {
        return system.name
    }
}
